// Branded partner invitation email, sent only at the inviting user's request.
// Does not trust client-supplied invitation tokens or sender identities.
const env=(name:string)=>(Deno.env.get(name)??"").trim();
const json=(status:number,body:unknown)=>new Response(JSON.stringify(body),{
  status,headers:{"content-type":"application/json","cache-control":"no-store",
    "x-content-type-options":"nosniff","referrer-policy":"no-referrer"}});
const escapeHtml=(v:string)=>v.replace(/[&<>"']/g,
  (x)=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[x]!));
function validStoreUrl(value:string,kind:"play"|"apple"):string{
  try{
    const uri=new URL(value);
    return uri.protocol==="https:" &&
      (kind==="play" ? uri.hostname==="play.google.com" &&
        uri.pathname==="/store/apps/details" &&
        uri.searchParams.get("id")==="live.onespace.app"
        : uri.hostname==="apps.apple.com" &&
          (uri.pathname.includes("/app/") && /\/id[0-9]+$/.test(uri.pathname))) ? uri.toString() : "";
  }catch{return "";}
}
function storePanel(url:string,kind:"play"|"apple"):string{
  const name=kind==="play"?"Google Play":"App Store";
  if(!url) return `<td style="padding:8px 5px"><div style="display:inline-block;min-width:140px;padding:10px 12px;border:1px solid #D8DFE6;border-radius:9px;background:#F4F7F9;color:#51657A;text-align:center;font-size:12px">${name}<br><strong style="font-size:13px;color:#14213D">Coming soon</strong></div></td>`;
  const src=kind==="play"?
    "https://play.google.com/intl/en_us/badges/images/generic/en_badge_web_generic.png":
    "https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83";
  return `<td style="padding:8px 5px"><a href="${escapeHtml(url)}"><img src="${escapeHtml(src)}" alt="${name}" width="145" style="display:block;max-width:145px;height:auto;border:0"></a></td>`;
}
function renderEmail(name:string,code:string,expiresAt:string,isQa:boolean){
  const site="https://onespace.live";
  const link=new URL(isQa?"/qa-invite/":"/app-invite/",site);
  link.searchParams.set("code",code);
  const safeUrl=escapeHtml(link.toString());
  const sender=escapeHtml(name||"Your partner");
  const play=validStoreUrl(env("ONESPACE_PLAY_STORE_URL"),"play");
  const apple=validStoreUrl(env("ONESPACE_APP_STORE_URL"),"apple");
  // Invitations last 48 hours from creation; a resend keeps the original end.
  const hours=Math.max(1,Math.ceil((new Date(expiresAt).getTime()-Date.now())/3600000));
  const left=hours===1?"1 hour":`${hours} hours`;
  const text=`${name||"Your partner"} invited you to OneSpace!

A little space for us — to remember, plan, and stay close.

Open your invitation:
${link.toString()}

If OneSpace is already installed, select Open in OneSpace on that page.
If it is not installed, follow the instructions on the invitation page.

Manual code (only if needed):
${code}

This invitation expires in ${left}. The code is the same when resent.

OneSpace
Two of Us. One Space.
https://onespace.live
support@onespace.live`;
  const html=`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;background:#F3F6FA;font-family:Arial,Helvetica,sans-serif;color:#14213D">
<span style="display:none;max-height:0;overflow:hidden;opacity:0">A little space for us. Your private OneSpace invitation is inside.</span>
<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:#F3F6FA"><tr><td align="center" style="padding:28px 12px">
<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:560px;background:white;border:1px solid #E3EAF0;border-radius:16px">
<tr><td style="padding:30px 28px 12px">
<img alt="OneSpace" src="https://onespace.live/assets/icon-512.png" width="52" height="52" style="display:block;border:0">
<h1 style="font-size:25px;line-height:1.28;margin:19px 0 12px;color:#14213D">A little space for us.</h1>
<p style="font-size:16px;line-height:1.65;color:#354B63;margin:0 0 14px"><strong>${sender}</strong> has invited you to share a private space on OneSpace.</p>
<p style="font-size:15px;line-height:1.65;color:#354B63;margin:0 0 18px">A place to remember little things, make plans, and stay connected.</p>
<table role="presentation" cellpadding="0" cellspacing="0"><tr><td style="background:#234D82;border-radius:10px;padding:15px 24px">
<a href="${safeUrl}" style="color:#ffffff;font-size:16px;font-weight:bold;text-decoration:none;display:inline-block">Accept your invitation</a></td></tr></table>
<p style="font-size:13px;line-height:1.65;color:#51657A;margin-top:18px">If the button doesn't work, open this secure link:<br>
<a href="${safeUrl}" style="color:#234D82;text-decoration:underline;word-break:break-all">${safeUrl}</a></p>
<p style="font-size:13px;color:#51657A;line-height:1.6;margin:18px 0 6px">Need to enter the code manually?</p>
<p style="padding:12px;background:#F2F6F9;font:12px/1.7 monospace;word-break:break-all;color:#14213D">${escapeHtml(code)}</p>
<p style="font-size:12px;color:#51657A;line-height:1.6">This invitation expires in ${escapeHtml(left)}. Resending does not extend it.</p>
</td></tr>
<tr><td style="padding:8px 23px 24px"><p style="font-size:13px;color:#51657A;margin:4px 5px">OneSpace for your phone</p>
<table role="presentation" cellpadding="0" cellspacing="0"><tr>${storePanel(play,"play")}${storePanel(apple,"apple")}</tr></table>
</td></tr>
<tr><td style="padding:18px 28px;border-top:1px solid #E3EAF0">
<table role="presentation" cellpadding="0" cellspacing="0"><tr>
<td style="vertical-align:middle;padding-right:12px"><img src="https://onespace.live/assets/icon-512.png" alt="" width="40" height="40" style="display:block"></td>
<td><strong style="font-size:20px;color:#14213D">OneSpace</strong><br>
<span style="font-size:12px;color:#51657A">Two of Us. One Space.</span><br>
<a href="${site}" style="font-size:12px;color:#234D82;text-decoration:none">onespace.live</a><br>
<a href="mailto:support@onespace.live" style="font-size:12px;color:#51657A;text-decoration:none">support@onespace.live</a></td></tr></table>
</td></tr></table>
</td></tr></table></body></html>`;
  return {subject:"A little space for us — your OneSpace invitation",text,html};
}
async function serviceRpc<T>(name:string,params:Record<string,unknown>):Promise<T>{
  const root=env("SUPABASE_URL"),key=env("SUPABASE_SERVICE_ROLE_KEY");
  const result=await fetch(root+"/rest/v1/rpc/"+name,{
    method:"POST",headers:{apikey:key,Authorization:"Bearer "+key,"content-type":"application/json"},
    body:JSON.stringify(params),
  });
  if(!result.ok)throw new Error("Rate-limit guard unavailable");
  return await result.json() as T;
}
Deno.serve(async(req)=>{
  if(req.method!=="POST")return json(405,{error:"POST required"});
  const bearer=req.headers.get("authorization")??"";
  if(!/^Bearer [^\s]+$/.test(bearer))return json(401,{error:"Sign in required"});
  const root=env("SUPABASE_URL"),anon=env("SUPABASE_ANON_KEY"),
    service=env("SUPABASE_SERVICE_ROLE_KEY"),resend=env("RESEND_API_KEY");
  if(!root||!anon||!service||!resend)return json(503,{error:"Email sending is not configured"});
  let body:Record<string,unknown>;
  try{
    const raw=await req.text();
    if(raw.length>2048)return json(413,{error:"Request too large"});
    body=JSON.parse(raw);
    if(!body || Array.isArray(body) || typeof body!=="object")
      return json(400,{error:"Invalid request"});
  }catch{return json(400,{error:"Invalid request"});}
  const recipient=typeof body.recipient_email==="string"?body.recipient_email.trim().toLowerCase():"";
  const space=typeof body.space_id==="string"?body.space_id:"";
  if(recipient.length>254||! /^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(recipient)||
     !/^[0-9a-f-]{36}$/i.test(space))return json(400,{error:"Enter a valid email address"});
  const userResult=await fetch(root+"/auth/v1/user",{
    headers:{apikey:anon,Authorization:bearer}});
  if(!userResult.ok)return json(401,{error:"Your session has expired"});
  const user=await userResult.json();
  if(!user?.id||typeof user.id!=="string")return json(401,{error:"Sign in required"});
  if(typeof user.email==="string"&&recipient===user.email.toLowerCase())
    return json(400,{error:"You cannot invite your own email"});
  const query=new URL(root+"/rest/v1/space_invitations");
  query.searchParams.set("select","token,expires_at,invited_email,delivery_status");
  query.searchParams.set("space_id","eq."+space);
  query.searchParams.set("invited_by","eq."+user.id);
  query.searchParams.set("accepted_at","is.null");
  query.searchParams.set("revoked_at","is.null");
  query.searchParams.set("expires_at","gt."+new Date().toISOString());
  query.searchParams.set("order","expires_at.desc");
  query.searchParams.set("limit","1");
  // Authenticated user's RLS controls which invitation can be sent.
  const invitations=await fetch(query,{
    headers:{apikey:anon,Authorization:bearer,"accept":"application/json"}});
  if(!invitations.ok)return json(403,{error:"You cannot send this invitation"});
  const rows=await invitations.json();
  const invite=rows?.[0];
  if(!invite||!/^[0-9a-f]{64}$/.test(invite.token??""))
    return json(409,{error:"There is no active invitation to send"});
  // The code was created for exactly one recipient by the owner's
  // recipient-bound RPC. Never let callers send it to another address.
  if(!invite.invited_email || invite.invited_email!==recipient)
    return json(403,{error:"The recipient does not match the invitation"});
  const digestData=await crypto.subtle.digest("SHA-256",
    new TextEncoder().encode(recipient+"|"+resend.slice(-24)));
  const digest=Array.from(new Uint8Array(digestData)).map(x=>x.toString(16).padStart(2,"0")).join("");
  let permitted=false;
  try{permitted=await serviceRpc<boolean>("claim_app_invitation_email_send",{
    p_sender_id:user.id,p_space_id:space,p_recipient_digest:digest,
  });}catch{return json(503,{error:"Invitation rate limiter unavailable"});}
  if(!permitted)return json(429,{error:"Too many invitations. Try again later."});
  const profUrl=new URL(root+"/rest/v1/profiles");
  profUrl.searchParams.set("select","display_name");
  profUrl.searchParams.set("id","eq."+user.id);
  profUrl.searchParams.set("limit","1");
  let name="";
  try{
    const p=await fetch(profUrl,{headers:{apikey:anon,Authorization:bearer}});
    if(p.ok){const profile=(await p.json())?.[0];name=String(profile?.display_name??"").trim().slice(0,60);}
  }catch{}
  const msg=renderEmail(name,invite.token,invite.expires_at,
    root.includes("ugwrpeduzyzrujkizqfo"));
  let response:Response;
  try{response=await fetch("https://api.resend.com/emails",{
    method:"POST",
    headers:{Authorization:"Bearer "+resend,"content-type":"application/json",
      "Idempotency-Key":"app-invite-"+user.id+"-"+digest.slice(0,16)+"-"+Math.floor(Date.now()/900000)},
    body:JSON.stringify({
      from:"OneSpace <support@onespace.live>",to:[recipient],
      reply_to:"support@onespace.live",
      subject:msg.subject,html:msg.html,text:msg.text,
      tags:[{name:"type",value:"app_invitation"}],
    }),
  });}catch{return json(502,{error:"Email provider unavailable. You can copy the invitation instead."});}
  if(!response.ok){
    return json(502,{error:"Email could not be delivered. Use the copy option instead."});
  }
  // Provider acceptance does not prove delivery. Never claim 'delivered'.
  try {
    const url = new URL(root+"/rest/v1/space_invitations");
    url.searchParams.set("token", "eq."+invite.token);
    url.searchParams.set("invited_by", "eq."+user.id);
    await fetch(url, {
      method:"PATCH",
      headers:{apikey:service,Authorization:"Bearer "+service,
        "content-type":"application/json"},
      body:JSON.stringify({delivery_status:"sent",email_sent_at:new Date().toISOString()})
    });
  }catch{}
  return json(200,{ok:true});
});
