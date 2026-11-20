// QA ONLY: bridge actual locally encrypted .osa source records to the
// existing strict private task/trip restore *rehearsal*. This NEVER writes.
import {decryptVaultSubsetFile} from "./qa_vault_subset_osa.mjs";
import {planPrivateRestoreDryRun} from "./qa_private_restore_dry_run.mjs";

const SUPPORTED={
  tasks:["task_checklist_items","task_checklist_checks"],
  shared_trips:["trip_flight_options","trip_items","trip_messages"]
};
const PARENT={
  task_checklist_items:"tasks",
  task_checklist_checks:"tasks",
  trip_flight_options:"shared_trips",
  trip_items:"shared_trips",
  trip_messages:"shared_trips"
};
const fail=(reason)=>{throw new Error("Unsafe QA .osa restore rehearsal: "+reason);};
const obj=x=>x!==null&&typeof x==="object"&&!Array.isArray(x);

export async function rehearsePrivateRestoreFromOsa({
  archiveBytes,passphrase,ownerId,sourceSpaceId,newSpaceId
}){
  // AES-GCM, per-record SHA, original author, source space, media exclusions,
  // table allowlists and parent integrity are verified *before* any remapping.
  const checked=await decryptVaultSubsetFile(
    archiveBytes,passphrase,ownerId,sourceSpaceId);
  if(checked.verified_ciphertext!==true||
      checked.verified_record_snapshots!==true||
      checked.verified_source_origin!==false||
      checked.can_restore!==false||checked.is_verified_archive!==false)
    fail("unexpected trusted/restore authority flags");
  if(typeof newSpaceId!=="string"||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(newSpaceId)||
      newSpaceId.toLowerCase()===sourceSpaceId.toLowerCase())
    fail("target must be a distinct valid relationship space");

  const roots=new Map(),children=new Map(),unplanned=new Map();
  for(const rec of checked.manifest.records){
    let snapshot;
    try{snapshot=JSON.parse(rec.snapshot_json);}
    catch{fail("record JSON changed after verification");}
    if(!obj(snapshot))fail("invalid structured record");
    if(rec.kind==="root"&&Object.hasOwn(SUPPORTED,rec.source_table)){
      const id=rec.source_id.toLowerCase();
      roots.set(rec.source_table+"|"+id,rec);
      continue;
    }
    if(rec.kind==="child"&&Object.hasOwn(PARENT,rec.source_table)){
      const key=PARENT[rec.source_table]+"|"+rec.parent_id.toLowerCase();
      if(!children.has(key))children.set(key,new Map());
      const family=children.get(key);
      if(!family.has(rec.source_table))family.set(rec.source_table,[]);
      family.get(rec.source_table).push(rec);
      continue;
    }
    unplanned.set(rec.source_table,(unplanned.get(rec.source_table)??0)+1);
  }
  if(roots.size>500)fail("rehearsal root bound exceeded");
  const plans=[];
  let mapped=0;
  for(const [key,root] of roots){
    const kinds=SUPPORTED[root.source_table];
    const childMap=children.get(key)??new Map();
    const outputChildren=Object.fromEntries(kinds.map(k=>[k,[]]));
    let childrenCount=0;
    for(const [table,rows] of childMap){
      if(!kinds.includes(table))fail("unexpected descendant");
      for(const rec of rows){
        if(rec.parent_table!==root.source_table ||
            rec.parent_id.toLowerCase()!==root.source_id.toLowerCase())
          fail("descendant parent identity changed");
        outputChildren[table].push({
          source_id:rec.source_id,structured:JSON.parse(rec.snapshot_json)
        });
        childrenCount++;
      }
    }
    const payload={
      schema:root.source_table==="tasks"
        ?"onespace.private-task-checklist-preview.v1"
        :"onespace.private-trip-structured-preview.v1",
      owner_id:ownerId,
      source_space_id:sourceSpaceId,
      root:{
        table:root.source_table,source_id:root.source_id,
        structured:JSON.parse(root.snapshot_json)
      },
      children:outputChildren,
      child_record_count:childrenCount
    };
    // Existing strict planner rejects unreviewed columns and old partner
    // references, generates fresh IDs and remaps checklist child FK edges.
    const plan=planPrivateRestoreDryRun(payload,{ownerId,newSpaceId});
    if(plan.can_write!==false||plan.can_restore!==false||
        plan.safe_to_separate!==false||plan.is_verified_archive!==false)
      fail("preview granted dangerous authority");
    mapped+=plan.id_mappings.length;
    plans.push(plan);
  }
  // Every eligible child must be accounted for; do not silently leave a child.
  const plannedChildren=plans.reduce(
    (count,plan)=>count+plan.id_mappings.length-1,0);
  const actualChildren=[...children.values()].reduce(
    (sum,fam)=>sum+[...fam.values()].reduce((n,rows)=>n+rows.length,0),0);
  if(plannedChildren!==actualChildren)fail("unplanned supported dependent");
  if(mapped>checked.manifest.record_count)fail("invalid mapped record count");

  return {
    format:"onespace.qa.osa-private-restore-rehearsal.v1",
    original_space_id:sourceSpaceId,destination_space_id:newSpaceId,
    owner_id:ownerId,subset_sha256:checked.evidence.subset_sha256,
    verified_encryption:true,verified_source_snapshots:true,
    verified_source_origin:false,
    mapped_private_record_count:mapped,
    unplanned_record_count:checked.manifest.record_count-mapped,
    unplanned_table_counts:Object.fromEntries([...unplanned.entries()].sort()),
    plans,
    all_69_types_packaged:false,
    private_restore_complete:false,shared_reference_restored:false,
    is_verified_archive:false,can_write:false,can_restore:false,
    safe_to_archive:false,safe_to_separate:false,
    media_included:false,documents_included:false,
    warning:"QA read-only rehearsal. Only reviewed private task/trip subtrees are mapped. No trusted archive issuance or database writes. Other private families and all original-pair shared reference content remain un-restored; media and uploaded documents are excluded."
  };
}
