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
    if(!sessionKey){
      sessionKey=(globalThis.crypto&&crypto.randomUUID?crypto.randomUUID():Date.now().toString(36)+'-'+Math.random().toString(36).slice(2)+'-'+Math.random().toString(36).slice(2));
      try{localStorage.setItem(storageKey,sessionKey);}catch{}
    }
    const params=new URLSearchParams(location.search);
    const gclid=params.get('gclid'),gbraid=params.get('gbraid'),wbraid=params.get('wbraid'),fbclid=params.get('fbclid');
    const payload={sessionKey,platform:gclid||gbraid||wbraid?'google_ads':fbclid?'meta_ads':null,gclid,gbraid,wbraid,fbclid,utmSource:params.get('utm_source'),utmMedium:params.get('utm_medium'),utmCampaign:params.get('utm_campaign'),utmTerm:params.get('utm_term'),utmContent:params.get('utm_content'),landingPage:location.href,referrer:document.referrer||null};
    const post=(path,body)=>fetch(apiBase+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),mode:'cors',credentials:'omit'});
    post('/api/marketing/track',payload).then(r=>r.ok?r.json():null).then(()=>post('/api/marketing/number',{sessionKey})).then(r=>r&&r.ok?r.json():null).then(data=>{
      if(!data||!data.available||!data.phoneNumber)return;
      document.querySelectorAll('[data-durfee-phone]').forEach(el=>{
        const number=data.phoneNumber;
        if(el instanceof HTMLAnchorElement)el.href='tel:'+number.replace(/[^+0-9]/g,'');
        if(el.getAttribute('data-durfee-phone')!=='href-only')el.textContent=number;
      });
    }).catch(()=>{});
    document.querySelectorAll('form').forEach(form=>{
      if(form.querySelector('input[name="durfee_marketing_session"]'))return;
      const input=document.createElement('input');input.type='hidden';input.name='durfee_marketing_session';input.value=sessionKey;form.appendChild(input);
    });
    globalThis.DurfeeMarketing={sessionKey};
  }catch{}
})();`;

export async function GET(){
  return new NextResponse(script,{status:200,headers:{'Content-Type':'application/javascript; charset=utf-8','Cache-Control':'public, max-age=300, s-maxage=3600','X-Content-Type-Options':'nosniff'}});
}
