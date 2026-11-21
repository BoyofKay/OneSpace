// QA-only deployed unscheduled JWT-protected file worker; service secret required.
// The account deletion request must be past its full 7 days, unpaired,
// original Storage owner intact, and service-only DB gate intentionally on.
// This worker never touches shared/relationship buckets or Auth users.
import {createClient} from "npm:@supabase/supabase-js@2.58.0";
import {validateAccountPurgeJob} from "../_shared/qa_account_private_media_purge_contract.mjs";
import {qaVaultSecretMatches} from "../_shared/qa_worker_secret.ts";

const env=(key:string)=>(Deno.env.get(key)??"").trim();
const answer=(code:number,data:Record<string,unknown>)=>
 new Response(JSON.stringify(data),{status:code,headers:{
  "content-type":"application/json","cache-control":"no-store",
  "x-content-type-options":"nosniff",
 }});
type Job={owner_id:string;bucket_id:string;object_path:string;lease_id:string};

Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return answer(405,{error:"POST required"});
 const url=env("SUPABASE_URL");
 const key=env("SUPABASE_SERVICE_ROLE_KEY");
 let project:URL;
 try{project=new URL(url);}catch{return answer(503,{error:"QA backend unavailable"});}
 if(project.protocol!=="https:"||
   !["ugwrpeduzyzrujkizqfo.supabase.co","letcgxbnblohhfyeuigz.supabase.co"].includes(project.hostname)||!key)
  return answer(503,{error:"QA-only project guard failed"});

 const db=createClient(url,key,{auth:{
  persistSession:false,autoRefreshToken:false,
 }});
 if(!await qaVaultSecretMatches(db,"onespace_qa_account_purge_secret",
   req.headers.get("x-onespace-qa-account-purge-secret")))
  return answer(401,{error:"Unauthorized"});
 let jobs:Job[];
 try{
  const {data,error}=await db.rpc("qa_claim_due_account_private_media",{p_limit:20});
  if(error||!Array.isArray(data))throw Error("Cannot lease eligible private files");
  jobs=data as Job[];
 }catch{return answer(503,{error:"Private file purge gate closed or unavailable"});}
 let removed=0,failed=0,invalid=0,ackFailed=0;
 for(const raw of jobs){
  const safe=validateAccountPurgeJob(raw);
  let done=false;
  if(safe){
   try{
    // Use the Storage API: direct SQL deletion leaves orphaned object bytes.
    // Failed or interrupted calls are safely retried with new DB leases.
    const {error}=await db.storage.from(safe.bucket_id)
      .remove([safe.object_path]);
    done=!error;
   }catch{done=false;}
  }else invalid++;
  try{
   const job=safe??raw;
   if(typeof job.owner_id!=="string"||typeof job.bucket_id!=="string"||
      typeof job.object_path!=="string"||typeof job.lease_id!=="string")
    throw Error("Malformed lease metadata");
   const {data,error}=await db.rpc("qa_ack_due_account_private_media",{
    p_owner_id:job.owner_id,p_bucket_id:job.bucket_id,
    p_object_path:job.object_path,p_lease_id:job.lease_id,
    p_succeeded:done,
   });
   if(error||data!==true)throw Error("Lease acknowledgement failed");
   if(done)removed++;else failed++;
  }catch{ackFailed++;}
 }
 const clean=failed===0&&invalid===0&&ackFailed===0;
 return answer(clean?200:503,{
  mode:"qa_due_unpaired_account_private_media_only",
  claimed:jobs.length,removed,failed,invalid,ack_failed:ackFailed,
  ...(clean?{}:{error:"Some file removals need retry or manual review"}),
 });
});
