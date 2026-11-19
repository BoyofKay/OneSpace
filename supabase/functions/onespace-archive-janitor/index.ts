// QA archive janitor. Never deletes shared/private live records.
// Remove only temporary *encrypted archive objects* whose recipient either
// explicitly saved a verified external copy or whose 30-day TTL passed.
// Uses the Storage API (not SQL deletes to storage.objects).
const env=(key:string)=>(Deno.env.get(key)??"").trim();
const json=(status:number,value:unknown)=>new Response(JSON.stringify(value),
  {status,headers:{"content-type":"application/json","cache-control":"no-store"}});
Deno.serve(async(req)=>{
  if(req.method!=="POST")return json(405,{error:"POST required"});
  const secret=env("ONESPACE_PUSH_CRON_SECRET");
  if(!secret||req.headers.get("x-onespace-push-secret")!==secret)
    return json(401,{error:"Unauthorized"});
  const base=env("SUPABASE_URL"),service=env("SUPABASE_SERVICE_ROLE_KEY");
  if(!base||!service)return json(503,{error:"Not configured"});
  const auth={apikey:service,Authorization:"Bearer "+service,
    "content-type":"application/json"};
  const rpc=async(name:string,payload:unknown)=>{
    const response=await fetch(base+"/rest/v1/rpc/"+name,
      {method:"POST",headers:auth,body:JSON.stringify(payload)});
    if(!response.ok)throw new Error("Archive RPC failed: "+response.status);
    return response.json();
  };
  let due:Array<{archive_id:string,object_path:string}>;
  try{due=await rpc("archives_due_for_purge_service",{});}
  catch{return json(503,{error:"Archive registry unavailable"});}
  const results={purged:0,failed:0};
  for(const item of due){
    if(!item?.archive_id||!item?.object_path){
      results.failed++;
      continue;
    }
    // Guard against deleting arbitrary Storage objects due to a corrupt row.
    if(!/^[0-9a-f-]{36}$/i.test(item.archive_id)||
       !/^[0-9a-f-]{36}\/[^.][a-zA-Z0-9_./-]{0,490}$/.test(item.object_path)||
       item.object_path.includes("..")){
      results.failed++;
      continue;
    }
    try{
      const remove=await fetch(base+"/storage/v1/object/onespace-archives",{
        method:"DELETE",headers:auth,
        body:JSON.stringify({prefixes:[item.object_path]})});
      if(!remove.ok)throw new Error("Storage delete rejected: "+remove.status);
      await rpc("finish_archive_purge_service",{
        p_archive_id:item.archive_id,p_error:null});
      results.purged++;
    }catch(error){
      results.failed++;
      const note=error instanceof Error?error.message:"Cleanup error";
      try{await rpc("finish_archive_purge_service",{
        p_archive_id:item.archive_id,p_error:note.slice(0,300)});
      }catch{}
    }
  }
  // A separate 24h TTL applies to QA encrypted *previews* only.
  // Never mix this staging table into the 30-day real archive workflow.
  const previews={preview_examined:0,preview_purged:0,preview_failed:0};
  try{
    const duePreviews=await rpc("qa_previews_due_for_purge_service",{}) as
      Array<{preview_id:string,object_path:string}>;
    previews.preview_examined=duePreviews.length;
    for(const item of duePreviews){
      const id=String(item?.preview_id??"");
      const path=String(item?.object_path??"");
      if(!/^[0-9a-f-]{36}$/i.test(id)||
         !/^[0-9a-f-]{36}\/qa-previews\/[0-9a-f-]{36}\.onespace-preview$/i.test(path)||
         path.includes("..")){
        previews.preview_failed++;
        continue;
      }
      try{
        const removed=await fetch(base+"/storage/v1/object/onespace-archives",{
          method:"DELETE",headers:auth,body:JSON.stringify({prefixes:[path]})});
        if(!removed.ok)throw new Error("Preview object deletion failed");
        const recorded=await rpc("qa_preview_finish_purge_service",{
          p_id:id});
        if(recorded!==true)throw new Error("Preview purge registry update failed");
        previews.preview_purged++;
      }catch{previews.preview_failed++;}
    }
  }catch{
    // Do not break 30-day archive cleanup if QA-only staging is temporarily
    // unavailable. Report this failure for operational monitoring.
    previews.preview_failed++;
  }
  // Separate 24h expiry for locally encrypted QA .osa subset files.
  // These are NOT actual ready archives or deletable relationship records.
  const subsets={subset_examined:0,subset_purged:0,subset_failed:0};
  try{
    const dueFiles=await rpc("qa_subset_due_purge_service",{}) as
      Array<{staging_id:string,object_path:string}>;
    subsets.subset_examined=dueFiles.length;
    for(const item of dueFiles){
      const id=String(item?.staging_id??"");
      const path=String(item?.object_path??"");
      const match=path.match(/^([0-9a-f-]{36})\/qa-subsets\/([0-9a-f-]{36})\.osa$/i);
      if(!/^[0-9a-f-]{36}$/i.test(id)||!match||
          match[2]!==id||path.includes("..")){
        subsets.subset_failed++;
        continue;
      }
      try{
        const removed=await fetch(base+"/storage/v1/object/onespace-archives",{
          method:"DELETE",headers:auth,body:JSON.stringify({prefixes:[path]})});
        if(!removed.ok)throw new Error("QA subset object cleanup failed");
        const recorded=await rpc("qa_subset_finish_purge_service",{p_id:id});
        if(recorded!==true)throw new Error("QA subset cleanup registry refused");
        subsets.subset_purged++;
      }catch{subsets.subset_failed++;}
    }
  }catch{subsets.subset_failed++;}
  return json(200,{examined:due.length,...results,...previews,...subsets});
});
