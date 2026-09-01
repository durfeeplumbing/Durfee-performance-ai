import { createSupabaseServerClient } from '@/lib/supabase/server';

const RESOURCES = [
  'appointments',
  'business_units',
  'customers',
  'invoices',
  'jobs',
  'locations',
  'memberships',
  'payments',
  'technicians',
] as const;

const MATCH_STATUSES = ['matched', 'unmatched', 'needs_review', 'ignored'] as const;

export type ServiceTitanCoverageRow = {
  resource: string;
  staged: number;
  latestSync: string | null;
  matched: number;
  unmatched: number;
  needsReview: number;
  ignored: number;
  mapped: number;
  mappingPercent: number;
};

export type ServiceTitanReadinessCoverage = {
  available: boolean;
  lastSuccessfulSync: string | null;
  lastError: string | null;
  totalStaged: number;
  totalMapped: number;
  totalUnmatched: number;
  overallMappingPercent: number;
  rows: ServiceTitanCoverageRow[];
  message?: string;
};

async function exactCount(query: any) {
  const { count, error } = await query;
  if (error) throw error;
  return Number(count ?? 0);
}

export async function getServiceTitanReadinessCoverage(): Promise<ServiceTitanReadinessCoverage> {
  const supabase = await createSupabaseServerClient();

  try {
    const [{ data: state, error: stateError }, ...resourceResults] = await Promise.all([
      supabase
        .from('service_titan_integration_state')
        .select('last_successful_sync,last_error')
        .eq('singleton', true)
        .maybeSingle(),
      ...RESOURCES.map(async (resource) => {
        const stagedPromise = exactCount(
          supabase.from('service_titan_records').select('id', { count: 'exact', head: true }).eq('resource', resource),
        );
        const latestPromise = supabase
          .from('service_titan_records')
          .select('synced_at')
          .eq('resource', resource)
          .order('synced_at', { ascending: false })
          .limit(1)
          .maybeSingle();
        const mappingPromises = MATCH_STATUSES.map((status) =>
          exactCount(
            supabase
              .from('service_titan_record_mappings')
              .select('id', { count: 'exact', head: true })
              .eq('resource', resource)
              .eq('match_status', status),
          ),
        );

        const [staged, latest, matched, unmatched, needsReview, ignored] = await Promise.all([
          stagedPromise,
          latestPromise,
          ...mappingPromises,
        ]);
        if (latest.error) throw latest.error;

        const mapped = matched + ignored;
        return {
          resource,
          staged,
          latestSync: latest.data?.synced_at ?? null,
          matched,
          unmatched,
          needsReview,
          ignored,
          mapped,
          mappingPercent: staged > 0 ? Math.round((mapped / staged) * 1000) / 10 : 0,
        } satisfies ServiceTitanCoverageRow;
      }),
    ]);

    if (stateError) throw stateError;
    const rows = resourceResults as ServiceTitanCoverageRow[];
    const totalStaged = rows.reduce((sum, row) => sum + row.staged, 0);
    const totalMapped = rows.reduce((sum, row) => sum + row.mapped, 0);
    const totalUnmatched = rows.reduce((sum, row) => sum + row.unmatched + row.needsReview, 0);

    return {
      available: true,
      lastSuccessfulSync: state?.last_successful_sync ?? null,
      lastError: state?.last_error ?? null,
      totalStaged,
      totalMapped,
      totalUnmatched,
      overallMappingPercent: totalStaged > 0 ? Math.round((totalMapped / totalStaged) * 1000) / 10 : 0,
      rows,
    };
  } catch (error) {
    return {
      available: false,
      lastSuccessfulSync: null,
      lastError: null,
      totalStaged: 0,
      totalMapped: 0,
      totalUnmatched: 0,
      overallMappingPercent: 0,
      rows: [],
      message: error instanceof Error ? error.message : 'ServiceTitan readiness coverage is unavailable.',
    };
  }
}
