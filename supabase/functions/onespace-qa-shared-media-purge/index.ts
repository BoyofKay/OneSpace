// QA-only deployed unscheduled JWT-protected endpoint; service secret required.
// Never run for a live space or account-owned bucket. Service-role RPC leases
// and verifies each retired-couple object; this function uses Storage.remove,
// never DELETE FROM storage.objects (which would orphan file bytes).
import {createClient} from "npm:@supabase/supabase-js@2.58.0";
import {validateMediaPurgeJob} from "../_shared/qa_shared_media_purge_contract.mjs";
import {qaVaultSecretMatches} from "../_shared/qa_worker_secret.ts";

const env=(key:string)=>(Deno.env.get(key)??"").trim();
const json=(status:number,body:Record<string,unknown>)=>
 new Response(JSON.stringify(body),{status,headers:{
  "content-type":"application/json","cache-control":"no-store",
  "x-content-type-options":"nosniff",
 }});
type Job={space_id:string;bucket_id:string;object_path:string;
 lease_id:string;expected_uploader_id:string};
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json(405,{error:"POST required"});
 const url=env("SUPABASE_URL");
 const service=env("SUPABASE_SERVICE_ROLE_KEY");
 let projectUrl:URL;
 try{projectUrl=new URL(url);}catch{return json(503,{error:"QA backend not configured"});}
 if(projectUrl.protocol!=="https:"||
   projectUrl.hostname!=="ugwrpeduzyzrujkizqfo.supabase.co"||
   !service)return json(503,{error:"QA-only backend verification failed"});

 const db=createClient(url,service,{
  auth:{persistSession:false,autoRefreshToken:false},
 });
 if(!await qaVaultSecretMatches(db,"onespace_qa_media_purge_secret",
   req.headers.get("x-onespace-qa-media-purge-secret")))
  return json(401,{error:"Unauthorized"});
 let claimed:Job[];
 try{
  const {data,error}=await db.rpc("qa_claim_shared_media_purge",{p_limit:20});
  if(error||!Array.isArray(data))
   throw new Error("Unable to lease queue");
  claimed=data as Job[];
 }catch{
  return json(503,{error:"QA shared-media queue unavailable"});
 }
 let removed=0,failed=0,invalid=0,ackFailed=0;
 for(const raw of claimed){
  const safe=validateMediaPurgeJob(raw);
  let success=false;
  if(safe){
   try{
    // Storage API deletes actual bytes and metadata; this is NOT a SQL delete.
    // A repeated already-absent object is safe for idempotent retries.
    const {error}=await db.storage.from(safe.bucket_id)
      .remove([safe.object_path]);
    success=!error;
   }catch{success=false;}
  }else invalid++;
  try{
   const j=safe??raw;
   if(typeof j.space_id!=="string"||typeof j.bucket_id!=="string"||
      typeof j.object_path!=="string"||typeof j.lease_id!=="string")
     throw new Error("Invalid lease metadata");
   const {data,error}=await db.rpc("qa_ack_shared_media_purge",{
    p_space_id:j.space_id,p_bucket_id:j.bucket_id,
    p_object_path:j.object_path,p_lease_id:j.lease_id,
    p_succeeded:success,
   });
   if(error||data!==true)throw new Error("Media acknowledgment rejected");
   if(success)removed++;
   else failed++;
  }catch{ackFailed++;}
 }
 const allOk=failed===0&&invalid===0&&ackFailed===0;
 return json(allOk?200:503,{
  mode:"qa_retired_pair_only",
  claimed:claimed.length,removed,failed,invalid,ack_failed:ackFailed,
  ...(allOk?{}:{error:"Some physical file purges require retry or review"}),
 });
});
