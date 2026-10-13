import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
function load(path,imports={}){const source=ts.transpileModule(readFileSync(new URL(path,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;const exports={};vm.runInNewContext(source,{exports,require:(name)=>imports[name],URL,Map,Set,Number,String,Date});return exports;}
const events=load('../lib/marketing/website-events.ts');
const attribution=load('../lib/marketing/attribution.ts',{'./website-events':events});
test('page collection strips query strings and rejects other sites',()=>{assert.equal(events.safeWebsitePath('https://capecodplumber.com/services/drain-cleaning?email=private@example.com'),'\/services/drain-cleaning');assert.equal(events.safeWebsitePath('https://other.example/test'),null);assert.equal(events.safeWebsitePath('//other.example/test'),null);});
test('collector rejects unknown event kinds and invalid session IDs',()=>{assert.equal(events.normalizeWebsiteEvent({kind:'booked_job',eventId:'fake',sessionId:'fake'}),null);});
test('call page attribution requires an explicit call ID',()=>{const calls=[{id:'123',landingPage:null}];attribution.applyCallAttributions(calls,[{campaignId:10,url:'https://capecodplumber.com/drains'}]);assert.equal(calls[0].landingPage,null);attribution.applyCallAttributions(calls,[{call:{id:123},job:{id:456},attribution:{landingPageUrl:'https://capecodplumber.com/drains?name=private'}}]);assert.equal(calls[0].landingPage,'/drains');});
test('job revenue is counted once and ambiguous pages get no revenue credit',()=>{const calls=[{jobId:'10',landingPage:'/drains'},{jobId:'10',landingPage:'/drains'}];const jobs=[{id:10,total:300,jobStatus:'Completed'}];let r=attribution.uniquePageJobRevenue(calls,jobs);assert.equal(r.pages.get('/drains').jobTotal,300);assert.equal(r.pages.get('/drains').jobs,1);r=attribution.uniquePageJobRevenue([...calls,{jobId:'10',landingPage:'/plumbing'}],jobs);assert.equal(r.pages.size,0);assert.equal(r.ambiguousJobs,1);});

test('telecom bundle uses the lead call ID and missing jobs are unavailable',()=>{const c=attribution.normalizeCall({id:900,leadCall:{id:123,receivedOn:'2026-10-13T10:00:00Z',direction:'Inbound'}});assert.equal(c.id,'123');assert.equal(c.jobId,null);assert.equal(attribution.uniquePageJobRevenue([{jobId:'99',landingPage:'/drains'}],[]).pages.get('/drains').missingJobs,1);});

test('missing attribution does not become a homepage visit',()=>{for(const v of ['', ' ', 'unknown', '?source=google', null])assert.equal(events.safeWebsitePath(v),null);});
