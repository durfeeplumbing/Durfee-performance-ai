import { NextResponse } from 'next/server';

export const runtime='nodejs';
export const dynamic='force-dynamic';

const script=String.raw`(()=>{
  try{
    const current=document.currentScript;
    const apiBase=current&&current.src?new URL(current.src).origin:'';
    if(!apiBase)return;
    const storageKey='durfee_marketing_session';
    let sessionKey='';
    try{sessionKey=localStorage.getItem(storageKey)||'';}catch{}
    if(!sessionKey){sessionKey=(globalThis.crypto&&crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)+'-'+Math.random().toString(36).slice(2));try{localStorage.setItem(storageKey,sessionKey);}catch{}}
    const params=new URLSearchParams(location.search);
    const first=(...names)=>{for(const n of names){const v=params.get(n);if(v)return v;}return null;};
    const gclid=first('gclid'),gbraid=first('gbraid'),wbraid=first('wbraid'),fbclid=first('fbclid');
    const google=Boolean(gclid||gbraid||wbraid),meta=Boolean(fbclid);
    const payload={sessionKey,platform:google?'google_ads':meta?'meta_ads':null,gclid,gbraid,wbraid,fbclid,utmSource:first('utm_source'),utmMedium:first('utm_medium'),utmCampaign:first('utm_campaign'),utmTerm:first('utm_term'),utmContent:first('utm_content'),landingPage:location.href,referrer:document.referrer||null,externalCampaignId:google?first('campaignid','campaign_id'):meta?first('campaign_id'):first('campaignid','campaign_id'),externalGroupId:google?first('adgroupid','ad_group_id'):meta?first('adset_id','adsetid'):first('adgroupid','adset_id'),externalAdId:google?first('creative','ad_id'):meta?first('ad_id'):first('creative','ad_id'),device:first('device'),network:first('network'),matchType:first('matchtype','match_type')};
    const post=(path,body,keepalive=false)=>fetch(apiBase+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),mode:'cors',credentials:'omit',keepalive}).catch(()=>null);
    post('/api/marketing/track',payload).then(r=>r&&r.ok?r.json():null).then(()=>post('/api/marketing/number',{sessionKey})).then(r=>r&&r.ok?r.json():null).then(data=>{
      if(!data||!data.available||!data.phoneNumber)return;
      document.querySelectorAll('[data-durfee-phone]').forEach(el=>{const number=data.phoneNumber;if(el instanceof HTMLAnchorElement)el.href='tel:'+number.replace(/[^+0-9]/g,'');if(el.getAttribute('data-durfee-phone')!=='href-only')el.textContent=number;});
    }).catch(()=>{});
    const ensureSessionField=form=>{if(form.querySelector('input[name="durfee_marketing_session"]'))return;const input=document.createElement('input');input.type='hidden';input.name='durfee_marketing_session';input.value=sessionKey;form.appendChild(input);};
    document.querySelectorAll('form').forEach(ensureSessionField);
    const value=(form,kind,names)=>{const explicit=form.querySelector('[data-durfee-lead-field="'+kind+'"]');if(explicit&&'value' in explicit&&String(explicit.value||'').trim())return String(explicit.value).trim();for(const name of names){const el=form.querySelector('[name="'+name+'"],[name="'+name.toUpperCase()+'"]');if(el&&'value' in el&&String(el.value||'').trim())return String(el.value).trim();}return null;};
    document.addEventListener('submit',event=>{
      const form=event.target;if(!(form instanceof HTMLFormElement)||!form.matches('[data-durfee-lead]'))return;
      ensureSessionField(form);
      const phone=value(form,'phone',['phone','phone_number','telephone','tel']);const email=value(form,'email',['email','email_address']);if(!phone&&!email)return;
      const name=value(form,'name',['name','full_name','fullname','customer_name']);const serviceRequest=value(form,'service',['service_request','message','comments','description','problem','service']);
      const formName=form.getAttribute('data-durfee-lead')||form.getAttribute('name')||form.id||'website-form';
      post('/api/marketing/lead',{sessionKey,formName,name,phone,email,serviceRequest,landingPage:location.href},true);
    },true);
    const observer=new MutationObserver(()=>document.querySelectorAll('form').forEach(ensureSessionField));observer.observe(document.documentElement,{childList:true,subtree:true});
    globalThis.DurfeeMarketing={sessionKey,captureLead:(lead)=>post('/api/marketing/lead',{...lead,sessionKey,landingPage:lead&&lead.landingPage||location.href},true)};
  }catch{}
})();`;

export async function GET(){return new NextResponse(script,{status:200,headers:{'Content-Type':'application/javascript; charset=utf-8','Cache-Control':'public, max-age=300, s-maxage=3600','X-Content-Type-Options':'nosniff'}});}
