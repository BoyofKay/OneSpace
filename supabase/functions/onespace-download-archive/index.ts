// QA: authenticated transfer of a previously *verified, encrypted* archive.
// The endpoint NEVER deletes or marks an archive downloaded. In particular,
// automatic app-private downloads do not qualify as external-download proof.
const env=(k:string)=>(Deno.env.get(k)??"").trim();
const json=(status:number,error:string)=>new Response(JSON.stringify({error}),{
  status,headers:{"content-type":"application/json","cache-control":"no-store"}});
Deno.serve(async(req)=>{
  if(req.method!=="POST")return json(405,"POST required");
  const bearer=req.headers.get("authorization")??"";
  if(!/^Bearer [^\s]+$/.test(bearer))return json(401,"Sign in required");
  const base=env("SUPABASE_URL");
  const anon=env("SUPABASE_ANON_KEY");
  const service=env("SUPABASE_SERVICE_ROLE_KEY");
  if(!base||!anon||!service)return json(503,"Archive service unavailable");
  const identity=await fetch(base+"/auth/v1/user",{
    headers:{apikey:anon,Authorization:bearer}});
  if(!identity.ok)return json(401,"Session expired");
  const me=await identity.json();
  if(typeof me.id!=="string")return json(401,"Sign in required");
  let payload:Record<string,unknown>;
  try{
    const body=await req.text();
    if(body.length>500)return json(413,"Request too large");
    payload=JSON.parse(body);
  }catch{return json(400,"Invalid request");}
  const id=String(payload.archive_id??"");
  if(!/^[0-9a-f-]{36}$/i.test(id))return json(400,"Invalid archive");
  const url=new URL(base+"/rest/v1/space_archives");
  url.searchParams.set("select","id,recipient_id,status,expires_at,encrypted_object_path,ciphertext_sha256,byte_length,archive_kind");
  url.searchParams.set("id","eq."+id);
  url.searchParams.set("recipient_id","eq."+me.id);
  url.searchParams.set("limit","1");
  const rowsResponse=await fetch(url,{headers:{apikey:anon,Authorization:bearer}});
  if(!rowsResponse.ok)return json(403,"Archive unavailable");
  const archive=(await rowsResponse.json())?.[0];
  if(!archive||archive.recipient_id!==me.id||archive.status!=="ready"||
     !archive.expires_at||Date.parse(archive.expires_at)<=Date.now())
    return json(404,"Archive unavailable");
  const path=String(archive.encrypted_object_path??"");
  if(!path.startsWith(me.id+"/")||path.includes("..")||path.length>500||
     !/^[0-9a-f]{64}$/.test(archive.ciphertext_sha256??""))
    return json(409,"Archive is not verified");
  const asset=await fetch(base+"/storage/v1/object/authenticated/onespace-archives/"+
    path.split("/").map(encodeURIComponent).join("/"),{
      headers:{apikey:service,Authorization:"Bearer "+service,
        "cache-control":"no-store"},
    });
  if(!asset.ok||!asset.body)return json(503,"Archive file unavailable");
  const headers=new Headers({
    "content-type":"application/octet-stream",
    "cache-control":"private, no-store, max-age=0",
    "x-content-type-options":"nosniff",
    "x-onespace-sha256":archive.ciphertext_sha256,
    "x-onespace-archive-id":id,
    "content-disposition":'attachment; filename="OneSpace-'+archive.archive_kind+
      '-'+id+'.onespace"',
  });
  if(archive.byte_length>0)headers.set("content-length",String(archive.byte_length));
  return new Response(asset.body,{status:200,headers});
});
