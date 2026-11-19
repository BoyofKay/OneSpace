import assert from "node:assert/strict";
import {test} from "node:test";
import {encryptPrivateStructuredPreview} from
  "../functions/_shared/structured_archive_crypto.mjs";
import {planPrivateRestoreDryRun,planPrivateRestoreFromEncryptedPreview} from
  "../functions/_shared/qa_private_restore_dry_run.mjs";

const owner="11111111-2222-4333-8444-555555555555";
const foreign="99999999-2222-4333-8444-555555555555";
const space="88888888-2222-4333-8444-555555555555";
const nextSpace="99999999-2222-4333-8444-444444444444";
const rootTask="aaaaaaaa-2222-4333-8444-555555555555";
const taskItem="bbbbbbbb-2222-4333-8444-555555555555";
const checkId="cccccccc-2222-4333-8444-555555555555";
const tripId="dddddddd-2222-4333-8444-555555555555";
const flightId="eeeeeeee-2222-4333-8444-555555555555";
const tripMessageId="ffffffff-2222-4333-8444-555555555555";
const password="Very strong recovery phrase for my private content";
const clone=x=>structuredClone(x);

const task={
  schema:"onespace.private-task-checklist-preview.v1",owner_id:owner,source_space_id:space,
  root:{table:"tasks",source_id:rootTask,structured:{
    id:rootTask,space_id:space,created_by:owner,
    title:"Private family tasks",visibility:"private",
    assigned_to:foreign,trip_id:tripId,
    migrated_to_list:"77777777-2222-4333-8444-555555555555"
  }},
  children:{
    task_checklist_items:[{source_id:taskItem,structured:{
      id:taskItem,task_id:rootTask,created_by:owner,
      title:"Remember my baby's birthday",legacy_assigned_to:foreign,
      legacy_task_id:"77777777-2222-4333-8444-555555555555"
    }}],
    task_checklist_checks:[{source_id:checkId,structured:{
      id:checkId,item_id:taskItem,task_id:rootTask,user_id:owner,
      completed:true,cycle_date:"2026-12-14"
    }}]
  },child_record_count:2
};
const trip={
  schema:"onespace.private-trip-structured-preview.v1",owner_id:owner,source_space_id:space,
  root:{table:"shared_trips",source_id:tripId,structured:{
    id:tripId,space_id:space,created_by:owner,visibility:"private",
    title:"A precious private trip",traveler_id:foreign
  }},
  children:{
    trip_flight_options:[{source_id:flightId,structured:{
      id:flightId,trip_id:tripId,created_by:owner,
      title:"Morning flight",notes:"We saw the sunrise"
    }}],
    trip_items:[],
    trip_messages:[{source_id:tripMessageId,structured:{
      id:tripMessageId,trip_id:tripId,created_by:owner,body:"A lovely memory"
    }}]
  },child_record_count:2
};
const preview=payload=>({
  payload,media_included:false,documents_included:false,encrypted:false,
  can_restore:false,is_verified_archive:false
});

test("read-only owner-specific remap generates distinct fresh IDs and valid child references",()=>{
  const plan=planPrivateRestoreDryRun(task,{ownerId:owner,newSpaceId:nextSpace});
  assert.equal(plan.can_write,false);
  assert.equal(plan.can_restore,false);
  assert.equal(plan.safe_to_separate,false);
  assert.equal(plan.is_verified_archive,false);
  assert.equal(plan.source_family,"tasks");
  assert.equal(plan.rows.root.space_id,nextSpace);
  assert.equal(plan.rows.root.created_by,owner);
  assert.equal(plan.rows.root.title,"Private family tasks");
  assert.equal(plan.rows.root.visibility,"private");
  assert.equal(plan.id_mappings.length,3);
  assert.equal(new Set(plan.id_mappings.map(x=>x.new_id)).size,3);
  assert.ok(!plan.id_mappings.some(x=>x.old_id===x.new_id));
  const rootNew=plan.rows.root.id;
  const itemNew=plan.rows.children.task_checklist_items[0].id;
  const checkNew=plan.rows.children.task_checklist_checks[0];
  assert.equal(plan.rows.children.task_checklist_items[0].task_id,rootNew);
  assert.equal(checkNew.task_id,rootNew);
  assert.equal(checkNew.item_id,itemNew);
  assert.equal(checkNew.user_id,owner);
  assert.equal(checkNew.completed,true);
  assert.equal(plan.rows.children.task_checklist_items[0].title,"Remember my baby's birthday");
  for(const key of ["assigned_to","trip_id","migrated_to_list"]){
    assert.equal(key in plan.rows.root,false);
  }
  assert.equal("legacy_assigned_to" in plan.rows.children.task_checklist_items[0],false);
  assert.equal(plan.dropped_external_references.length,5);
  assert.equal(task.root.structured.assigned_to,foreign);
  assert.equal(task.children.task_checklist_checks[0].structured.item_id,taskItem);
});
test("private trip remap preserves written memories but removes old traveler identity",()=>{
  const plan=planPrivateRestoreDryRun(trip,{ownerId:owner,newSpaceId:nextSpace});
  assert.equal(plan.source_family,"shared_trips");
  assert.equal(plan.rows.root.title,"A precious private trip");
  assert.equal("traveler_id" in plan.rows.root,false);
  const children=[...plan.rows.children.trip_flight_options,...plan.rows.children.trip_messages];
  assert.equal(children.length,2);
  for(const row of children){
    assert.equal(row.trip_id,plan.rows.root.id);
    assert.equal(row.created_by,owner);
  }
  assert.equal(children[0].notes,"We saw the sunrise");
  assert.equal(children[1].body,"A lovely memory");
});
test("encrypted round trip can produce a plan but never authorize actual restoration",async()=>{
  const sealed=await encryptPrivateStructuredPreview(preview(task),password);
  const planned=await planPrivateRestoreFromEncryptedPreview(
    sealed,password,owner,nextSpace);
  assert.equal(planned.rows.children.task_checklist_checks[0].completed,true);
  assert.equal(planned.can_write,false);
  assert.equal(planned.can_restore,false);
  assert.equal(planned.is_verified_archive,false);
  await assert.rejects(planPrivateRestoreFromEncryptedPreview(
    sealed,"A deliberately wrong recovery passphrase",owner,nextSpace));
  await assert.rejects(planPrivateRestoreFromEncryptedPreview(
    sealed,password,foreign,nextSpace));
});
test("orphan/foreign child data fails before it can generate a fake restore plan",()=>{
  const corruptions=[
    p=>{p.children.task_checklist_checks[0].structured.item_id=tripId},
    p=>{p.children.task_checklist_checks[0].structured.task_id=tripId},
    p=>{p.children.task_checklist_checks[0].structured.user_id=foreign},
    p=>{p.children.task_checklist_items[0].structured.created_by=foreign},
    p=>{p.children.task_checklist_items[0].structured.task_id=tripId},
    p=>{p.children.task_checklist_items[0].structured.id=tripId},
    p=>{p.children.task_checklist_items[0].source_id=rootTask},
    p=>{p.child_record_count=1},
    p=>{p.root.structured.created_by=foreign},
    p=>{p.root.structured.visibility="shared"},
    p=>{p.root.structured.space_id=nextSpace},
    p=>{p.root.source_id=tripId},
    p=>{p.children.unknown_injected_records=[]},
    p=>{p.root.structured.unreviewed_future_column="unsafe"},
    p=>{p.children.task_checklist_items[0].structured.injected_status="unsafe"},
    p=>{delete p.children.task_checklist_checks},
    p=>{p.children.task_checklist_items[0].structured.file_path="secret.jpg"},
    p=>{p.children.task_checklist_items[0].structured.title=
      "photo: /storage/v1/object/authenticated/family.jpg"}
  ];
  for(const mutate of corruptions){
    const altered=clone(task);mutate(altered);
    assert.throws(
      ()=>planPrivateRestoreDryRun(altered,{ownerId:owner,newSpaceId:nextSpace}),
      /Unsafe private restore preview/
    );
  }
});
test("owner and new relationship space are non-transferable",()=>{
  assert.throws(()=>planPrivateRestoreDryRun(task,{ownerId:foreign,newSpaceId:nextSpace}));
  assert.throws(()=>planPrivateRestoreDryRun(task,{ownerId:owner,newSpaceId:space}));
  assert.throws(()=>planPrivateRestoreDryRun(task,{ownerId:owner,newSpaceId:"bad-id"}));
  const foreignTrip=clone(trip);
  foreignTrip.children.trip_messages[0].structured.created_by=foreign;
  assert.throws(()=>planPrivateRestoreDryRun(foreignTrip,{
    ownerId:owner,newSpaceId:nextSpace}));
  const sharedTrip=clone(trip);
  sharedTrip.root.structured.visibility="shared";
  assert.throws(()=>planPrivateRestoreDryRun(sharedTrip,{
    ownerId:owner,newSpaceId:nextSpace}));
});
