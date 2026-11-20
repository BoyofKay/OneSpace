// QA-only cron worker: durable 69-family source census for original members.
// It NEVER exports records, encrypts files, edits membership or deletes users.
// It reports only real identified vs archived counts in the recipient's RLS row.
const REF="ugwrpeduzyzrujkizqfo.supabase.co";
const env=(name:string)=>(Deno.env.get(name)??"").trim();
const json=(status:number,data:Record<string,unknown>)=>
 new Response(JSON.stringify(data),{status,headers:{
   "content-type":"application/json","cache-control":"no-store",
   "x-content-type-options":"nosniff"
 }});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return json(405,{error:"POST required"});
 const secret=env("ONESPACE_PUSH_CRON_SECRET");
 if(!secret||req.headers.get("x-onespace-push-secret")!==secret)
   return json(401,{error:"Unauthorized"});
 const base=env("SUPABASE_URL"), key=env("SUPABASE_SERVICE_ROLE_KEY");
 if(!base||!key||new URL(base).hostname!==REF)
   return json(503,{error:"QA inventory worker unavailable"});
 let r:Response;
 try{
   r=await fetch(base+"/rest/v1/rpc/qa_archive_inventory_service",{
    method:"POST",
    headers:{"apikey":key,"authorization":"Bearer "+key,
      "content-type":"application/json"},
    body:JSON.stringify({p_limit:4}),
    signal:AbortSignal.timeout(90000),
   });
 }catch{return json(503,{error:"Inventory source unavailable"});}
 if(!r.ok) return json(503,{error:"Inventory source verification failed"});
 let result:Record<string,unknown>;
 try{result=await r.json()}
 catch{return json(503,{error:"Inventory result missing"})}
 if(!result||typeof result.jobs_examined!=="number"||
    typeof result.recipients_inventoried!=="number"||
    typeof result.recipients_blocked!=="number"||
    result.encrypted_archives_created!==0||
    result.lifecycle_changes_executed!==0)
   return json(503,{error:"Invalid inventory confirmation"});
 return json(200,{
  stage:"source_inventory_only",...result,
  encrypted_archives_issued:0,
  relationship_change_completed:false
 });
});
