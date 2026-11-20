import assert from "node:assert/strict";
import {test} from "node:test";
import {createHash} from "node:crypto";
import {encryptVaultSubsetFile} from
  "../functions/_shared/qa_vault_subset_osa.mjs";
import {rehearsePrivateRestoreFromOsa} from
  "../functions/_shared/qa_osa_subset_restore_plan.mjs";

const owner="11111111-2222-4333-8444-555555555555";
const other="22222222-2222-4333-8444-555555555555";
const space="99999999-2222-4333-8444-555555555555";
const destination="88888888-2222-4333-8444-555555555555";
const passphrase="QA rehearsal secret phrase 2026 verified";
const ids={
  task:"aaaaaaaa-2222-4333-8444-555555555555",
  item:"bbbbbbbb-2222-4333-8444-555555555555",
  check:"cccccccc-2222-4333-8444-555555555555",
  trip:"dddddddd-2222-4333-8444-555555555555",
  flight:"eeeeeeee-2222-4333-8444-555555555555",
  note:"ffffffff-2222-4333-8444-555555555555"
};
const sha=str=>createHash("sha256").update(str).digest("hex");
function record(kind,table,id,row,parentTable=null,parentId=null){
  const json=JSON.stringify(row);
  return {kind,source_table:table,source_id:id,
    parent_table:parentTable,parent_id:parentId,
    snapshot_json:json,snapshot_sha256:sha(json),
    snapshot_bytes:new TextEncoder().encode(json).length};
}
function fixture(){
  const rows=[
    record("root","tasks",ids.task,{
      id:ids.task,space_id:space,created_by:owner,visibility:"private",
      title:"My private task",assigned_to:other,trip_id:ids.trip
    }),
    record("root","shared_trips",ids.trip,{
      id:ids.trip,space_id:space,created_by:owner,visibility:"private",
      title:"My private trip",traveler_id:other
    }),
    record("root","notes",ids.note,{
      id:ids.note,space_id:space,created_by:owner,visibility:"private",
      title:"Not mapped yet",body:"Private note is still protected"
    }),
    record("child","task_checklist_items",ids.item,{
      id:ids.item,task_id:ids.task,created_by:owner,title:"Book hotel"
    },"tasks",ids.task),
    record("child","task_checklist_checks",ids.check,{
      id:ids.check,task_id:ids.task,item_id:ids.item,
      user_id:owner,completed:true
    },"tasks",ids.task),
    record("child","trip_flight_options",ids.flight,{
      id:ids.flight,trip_id:ids.trip,created_by:owner,
      title:"Sunrise flight",notes:"Saved written details"
    },"shared_trips",ids.trip)
  ];
  rows.sort((a,b)=>{
    const ak=a.kind+"|"+a.source_table+"|"+a.source_id;
    const bk=b.kind+"|"+b.source_table+"|"+b.source_id;
    return ak<bk?-1:ak>bk?1:0;
  });
  const summary=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
    "|"+rows.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
      r.snapshot_sha256).join("\n"));
  return {
    schema:"onespace.qa.private-vault-subset-manifest.v1",
    owner_id:owner,source_space_id:space,
    root_types_in_scope:14,dependent_types_in_scope:9,
    record_count:rows.length,
    root_record_count:rows.filter(r=>r.kind==="root").length,
    child_record_count:rows.filter(r=>r.kind==="child").length,
    snapshot_plaintext_bytes:rows.reduce((n,r)=>n+r.snapshot_bytes,0),
    subset_sha256:summary,records:rows,
    media_included:false,documents_included:false,
    all_69_types_packaged:false,source_manifest_scope_complete:true,
    archive_issued:false,server_signed:false,is_verified_archive:false,
    can_restore:false,safe_to_archive:false,safe_to_separate:false
  };
}
async function seal(manifest=fixture()){
  return encryptVaultSubsetFile(manifest,passphrase);
}
async function plan(file,opts={}){
  return rehearsePrivateRestoreFromOsa({
    archiveBytes:file,passphrase,ownerId:owner,
    sourceSpaceId:space,newSpaceId:destination,...opts
  });
}
test("actual AES-GCM .osa generates private task+trip remap without writes",async()=>{
  const result=await plan(await seal());
  assert.equal(result.verified_encryption,true);
  assert.equal(result.verified_source_snapshots,true);
  assert.equal(result.verified_source_origin,false);
  assert.equal(result.can_write,false);
  assert.equal(result.can_restore,false);
  assert.equal(result.safe_to_separate,false);
  assert.equal(result.private_restore_complete,false);
  assert.equal(result.plans.length,3);
  assert.equal(result.mapped_private_record_count,6);
  assert.equal(result.unplanned_record_count,0);
  assert.equal(result.unplanned_table_counts.notes,undefined);
  const task=result.plans.find(p=>p.source_family==="tasks");
  const trip=result.plans.find(p=>p.source_family==="shared_trips");
  assert.ok(task&&trip);
  assert.equal(task.rows.root.title,"My private task");
  assert.equal(task.rows.root.space_id,destination);
  assert.equal(task.rows.root.visibility,"private");
  assert.equal("assigned_to" in task.rows.root,false);
  assert.equal("trip_id" in task.rows.root,false);
  const item=task.rows.children.task_checklist_items[0];
  const check=task.rows.children.task_checklist_checks[0];
  assert.equal(item.task_id,task.rows.root.id);
  assert.equal(check.item_id,item.id);
  assert.equal(check.task_id,task.rows.root.id);
  assert.equal(check.user_id,owner);
  assert.equal(check.completed,true);
  assert.equal(trip.rows.root.title,"My private trip");
  assert.equal("traveler_id" in trip.rows.root,false);
  assert.equal(trip.rows.children.trip_flight_options[0].trip_id,trip.rows.root.id);
  assert.notEqual(trip.rows.root.id,ids.trip);
  assert.notEqual(task.rows.root.id,ids.task);
  const note=result.plans.find(p=>p.source_family==="notes");
  assert.equal(note.rows.root.title,"Not mapped yet");
  assert.equal(note.rows.root.body,"Private note is still protected");
  assert.equal(note.rows.root.space_id,destination);
  assert.equal(note.rows.root.visibility,"private");
  assert.notEqual(note.rows.root.id,ids.note);
  assert.equal(note.dependent_content_restored,false);
});
test("wrong user, old relationship boundary and wrong passphrase fail closed",async()=>{
  const file=await seal();
  await assert.rejects(()=>plan(file,{ownerId:other}));
  await assert.rejects(()=>plan(file,{newSpaceId:space}));
  await assert.rejects(()=>plan(file,{passphrase:"Incorrect password length sufficient"}));
});
test("private plan rejects unknown columns even if archive hashes are updated",async()=>{
  const manifest=fixture();
  const entry=manifest.records.find(r=>r.source_table==="tasks");
  const row=JSON.parse(entry.snapshot_json);
  row.new_unreviewed_private_field="Do not silently import";
  entry.snapshot_json=JSON.stringify(row);
  entry.snapshot_bytes=new TextEncoder().encode(entry.snapshot_json).length;
  entry.snapshot_sha256=sha(entry.snapshot_json);
  manifest.snapshot_plaintext_bytes=manifest.records.reduce(
    (n,r)=>n+r.snapshot_bytes,0);
  manifest.subset_sha256=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
    "|"+manifest.records.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
      r.snapshot_sha256).join("\n"));
  const file=await seal(manifest);
  await assert.rejects(()=>plan(file),/Unsafe private restore preview/);
});

function appendRootAndRefresh(m,table,id,row){
  m.records.push(record("root",table,id,row));
  m.records.sort((a,b)=>{
    const ak=a.kind+"|"+a.source_table+"|"+a.source_id;
    const bk=b.kind+"|"+b.source_table+"|"+b.source_id;
    return ak<bk?-1:ak>bk?1:0;
  });
  m.record_count=m.records.length;
  m.root_record_count=m.records.filter(r=>r.kind==="root").length;
  m.child_record_count=m.records.filter(r=>r.kind==="child").length;
  m.snapshot_plaintext_bytes=m.records.reduce((n,r)=>n+r.snapshot_bytes,0);
  m.subset_sha256=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
    "|"+m.records.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
      r.snapshot_sha256).join("\n"));
}
test("real encrypted goals and daily check-ins create distinct private-only root plans",async()=>{
  const m=fixture();
  const goal="77777777-2222-4333-8444-555555555555";
  const checkin="66666666-2222-4333-8444-555555555555";
  appendRootAndRefresh(m,"goals",goal,{
    id:goal,space_id:space,created_by:owner,visibility:"private",
    title:"Personal milestone",description:"Write my own plan",
    target_date:"2027-01-12",progress:20,status:"active"
  });
  appendRootAndRefresh(m,"daily_checkins",checkin,{
    id:checkin,space_id:space,created_by:owner,visibility:"private",
    checkin_date:"2026-11-20",mood:4,message:"Feeling hopeful",
    gratitude:"Time together"
  });
  const result=await plan(await seal(m));
  assert.equal(result.plans.length,5);
  assert.equal(result.mapped_private_record_count,8);
  assert.equal(result.unplanned_record_count,0);
  const g=result.plans.find(p=>p.source_family==="goals");
  const c=result.plans.find(p=>p.source_family==="daily_checkins");
  assert.equal(g.rows.root.title,"Personal milestone");
  assert.equal(c.rows.root.gratitude,"Time together");
  for(const p of [g,c]){
    assert.equal(p.rows.root.created_by,owner);
    assert.equal(p.rows.root.space_id,destination);
    assert.equal(p.rows.root.visibility,"private");
    assert.equal(p.can_write,false);
    assert.equal(p.can_restore,false);
    assert.notEqual(p.id_mappings[0].old_id,p.id_mappings[0].new_id);
  }
});
test("reviewed plain-text Quill formatting is kept without external links",async()=>{
  const m=fixture();
  const n=m.records.find(r=>r.source_table==="notes");
  const payload=JSON.parse(n.snapshot_json);
  payload.rich_delta=[{insert:"Private prose"},{insert:"\n",attributes:{bold:true,header:2}}];
  n.snapshot_json=JSON.stringify(payload);
  n.snapshot_sha256=sha(n.snapshot_json);
  n.snapshot_bytes=new TextEncoder().encode(n.snapshot_json).length;
  // Recompute the immutable source aggregate after fixture changes.
  m.snapshot_plaintext_bytes=m.records.reduce((t,r)=>t+r.snapshot_bytes,0);
  m.subset_sha256=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
    "|"+m.records.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
      r.snapshot_sha256).join("\n"));
  const result=await plan(await seal(m));
  assert.deepEqual(result.plans.find(p=>p.source_family==="notes")
    .rows.root.rich_delta,payload.rich_delta);
});
test("rehashed unreviewed rich-text links are rejected, not transplanted",async()=>{
  const m=fixture();
  const n=m.records.find(r=>r.source_table==="notes");
  const payload=JSON.parse(n.snapshot_json);
  payload.rich_delta=[{insert:"A link",attributes:{
    link:"https://example.org/other-relationship"
  }}];
  n.snapshot_json=JSON.stringify(payload);
  n.snapshot_sha256=sha(n.snapshot_json);
  n.snapshot_bytes=new TextEncoder().encode(n.snapshot_json).length;
  m.snapshot_plaintext_bytes=m.records.reduce((t,r)=>t+r.snapshot_bytes,0);
  m.subset_sha256=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+
    "|"+m.records.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
      r.snapshot_sha256).join("\n"));
  const sealed=await seal(m);
  await assert.rejects(()=>plan(sealed),
    /Unsafe QA standalone private root rehearsal/);
});
test("unreviewed root types remain counted as unplanned",async()=>{
  const m=fixture();
  const memory="55555555-2222-4333-8444-555555555555";
  appendRootAndRefresh(m,"memories",memory,{
    id:memory,space_id:space,created_by:owner,
    visibility:"private",title:"Needs reviewed dependency mapping"
  });
  const result=await plan(await seal(m));
  assert.equal(result.unplanned_record_count,1);
  assert.equal(result.unplanned_table_counts.memories,1);
  assert.equal(result.can_restore,false);
});
