import assert from "node:assert/strict";
import {createHash} from "node:crypto";
import {test} from "node:test";
import {mkdtemp,writeFile,readFile,rm} from "node:fs/promises";
import {join} from "node:path";
import {tmpdir} from "node:os";
import {
 encryptVaultSubsetFile,decryptVaultSubsetFile,verifyVaultSubsetManifest
} from "../functions/_shared/qa_vault_subset_osa.mjs";

const owner="11111111-2222-4333-8444-555555555555";
const other="22222222-2222-4333-8444-555555555555";
const space="99999999-2222-4333-8444-555555555555";
const otherSpace="88888888-2222-4333-8444-555555555555";
const noteId="aaaaaaaa-2222-4333-8444-555555555555";
const taskId="bbbbbbbb-2222-4333-8444-555555555555";
const itemId="cccccccc-2222-4333-8444-555555555555";
const checkId="dddddddd-2222-4333-8444-555555555555";
const password="very long QA vault archive recovery phrase";
const sha=src=>createHash("sha256").update(src).digest("hex");
const enc=new TextEncoder();
function entry(kind,table,id,snapshot,parent_table=null,parent_id=null){
 const snapshot_json=JSON.stringify(snapshot);
 return {kind,source_table:table,source_id:id,
  parent_table,parent_id,snapshot_json,
  snapshot_sha256:sha(snapshot_json),
  snapshot_bytes:enc.encode(snapshot_json).length};
}
function fixture(){
 const rows=[
  entry("root","notes",noteId,{
   id:noteId,space_id:space,created_by:owner,visibility:"private",
   title:"My personal written memory",body:"Walked in the sunshine"
  }),
  entry("root","tasks",taskId,{
   id:taskId,space_id:space,created_by:owner,visibility:"private",
   title:"Private checklist"
  }),
  entry("child","task_checklist_items",itemId,{
   id:itemId,task_id:taskId,created_by:owner,title:"Pack small gifts"
  },"tasks",taskId),
  entry("child","task_checklist_checks",checkId,{
   id:checkId,item_id:itemId,task_id:taskId,user_id:owner,
   completed:true,cycle_date:"2026-11-20"
  },"tasks",taskId)
 ];
 rows.sort((a,b)=>{
  const ak=a.kind+"|"+a.source_table+"|"+a.source_id;
  const bk=b.kind+"|"+b.source_table+"|"+b.source_id;
  return ak<bk?-1:ak>bk?1:0;
 });
 const digest=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+"|"+
   rows.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
     r.snapshot_sha256).join("\n"));
 return {schema:"onespace.qa.private-vault-subset-manifest.v1",
  owner_id:owner,source_space_id:space,root_types_in_scope:14,
  dependent_types_in_scope:9,record_count:rows.length,
  root_record_count:2,child_record_count:2,
  snapshot_plaintext_bytes:rows.reduce((t,r)=>t+r.snapshot_bytes,0),
  subset_sha256:digest,records:rows,
  media_included:false,documents_included:false,
  all_69_types_packaged:false,source_manifest_scope_complete:true,
  archive_issued:false,server_signed:false,is_verified_archive:false,
  can_restore:false,safe_to_archive:false,safe_to_separate:false};
}
const refresh=manifest=>{
 manifest.records.sort((a,b)=>{
  const ak=a.kind+"|"+a.source_table+"|"+a.source_id;
  const bk=b.kind+"|"+b.source_table+"|"+b.source_id;
  return ak<bk?-1:ak>bk?1:0;
 });
 manifest.record_count=manifest.records.length;
 manifest.root_record_count=manifest.records.filter(r=>r.kind==="root").length;
 manifest.child_record_count=manifest.records.filter(r=>r.kind==="child").length;
 manifest.snapshot_plaintext_bytes=manifest.records.reduce((n,r)=>n+r.snapshot_bytes,0);
 manifest.subset_sha256=sha("onespace.qa.private.vault-subset.v1|"+owner+"|"+space+"|"+
  manifest.records.map(r=>r.kind+"|"+r.source_table+"|"+r.source_id+"|"+
    r.snapshot_sha256).join("\n"));
};
const patch=(manifest,idx,update)=>{
 const v=JSON.parse(manifest.records[idx].snapshot_json);
 update(v);
 manifest.records[idx].snapshot_json=JSON.stringify(v);
 manifest.records[idx].snapshot_sha256=sha(manifest.records[idx].snapshot_json);
 manifest.records[idx].snapshot_bytes=enc.encode(manifest.records[idx].snapshot_json).length;
 refresh(manifest);
};
const fail=async body=>assert.rejects(body,/Invalid QA subset archive/);

test("real .osa bytes are independently written/read, AES-GCM decrypted and each snapshot SHA verified",async()=>{
 const manifest=fixture();
 const verified=await verifyVaultSubsetManifest(manifest,owner,space);
 assert.equal(verified.record_count,4);
 const data=await encryptVaultSubsetFile(manifest,password);
 assert.ok(data instanceof Uint8Array);
 assert.ok(data.length>100);
 const folder=await mkdtemp(join(tmpdir(),"onespace-qa-"));
 const path=join(folder,"owner-private-subset.osa");
 try{
  await writeFile(path,data,{mode:0o600});
  const actual=new Uint8Array(await readFile(path));
  const result=await decryptVaultSubsetFile(actual,password,owner,space);
  assert.equal(result.verified_ciphertext,true);
  assert.equal(result.verified_record_snapshots,true);
  assert.equal(result.verified_password_encryption,true);
  assert.equal(result.verified_source_origin,false);
  assert.equal(result.full_69_family_archive,false);
  assert.equal(result.can_restore,false);
  assert.equal(result.safe_to_separate,false);
  assert.equal(result.manifest.records.length,4);
  assert.match(result.manifest.records.find(r=>r.source_table==="notes").snapshot_json,
    /Walked in the sunshine/);
 }finally{await rm(folder,{recursive:true,force:true});}
});
test("wrong password, wrong owner and wrong relationship space always fail",async()=>{
 const data=await encryptVaultSubsetFile(fixture(),password);
 await fail(()=>decryptVaultSubsetFile(data,"different lengthy password here",owner,space));
 await fail(()=>decryptVaultSubsetFile(data,password,other,space));
 await fail(()=>decryptVaultSubsetFile(data,password,owner,otherSpace));
});
test("same-size ciphertext bit flip, truncated bytes and incorrect ciphertext digest all fail",async()=>{
 const file=await encryptVaultSubsetFile(fixture(),password);
 const obj=JSON.parse(new TextDecoder().decode(file));
 const original=atob(obj.ciphertext_b64);
 const flipped=String.fromCharCode(original.charCodeAt(0)^1)+original.slice(1);
 const changed={...obj,ciphertext_b64:btoa(flipped)};
 await fail(()=>decryptVaultSubsetFile(enc.encode(JSON.stringify(changed)),password,owner,space));
 const truncated={...obj,ciphertext_b64:btoa(original.slice(0,-1)),ciphertext_bytes:obj.ciphertext_bytes-1};
 await fail(()=>decryptVaultSubsetFile(enc.encode(JSON.stringify(truncated)),password,owner,space));
 const forged={...obj,ciphertext_sha256:"0".repeat(64)};
 await fail(()=>decryptVaultSubsetFile(enc.encode(JSON.stringify(forged)),password,owner,space));
});
test("plaintext per-record SHA tampering and dropped rows cannot produce an archive",async()=>{
 const altered=fixture();
 const idx=altered.records.findIndex(r=>r.source_table==="notes");
 altered.records[idx].snapshot_json=altered.records[idx].snapshot_json.replace(
  "Walked in the sunshine","A replaced narrative");
 await fail(()=>encryptVaultSubsetFile(altered,password));
 const lost=fixture();
 lost.records.pop();
 await fail(()=>encryptVaultSubsetFile(lost,password));
});
test("cross-author, orphan child, duplicate ID and unapproved future table are blocked",async()=>{
 const badAuthor=fixture();
 patch(badAuthor,badAuthor.records.findIndex(r=>r.source_table==="task_checklist_items"),
   row=>{row.created_by=other});
 await fail(()=>encryptVaultSubsetFile(badAuthor,password));
 const orphan=fixture();
 patch(orphan,orphan.records.findIndex(r=>r.source_table==="task_checklist_checks"),
   row=>{row.item_id=otherSpace});
 await fail(()=>encryptVaultSubsetFile(orphan,password));
 const badSpace=fixture();
 patch(badSpace,badSpace.records.findIndex(r=>r.source_table==="notes"),
   row=>{row.space_id=otherSpace});
 await fail(()=>encryptVaultSubsetFile(badSpace,password));
 const unknown=fixture();
 unknown.records[0].source_table="new_secret_table";
 refresh(unknown);
 await fail(()=>encryptVaultSubsetFile(unknown,password));
 const duplicate=fixture();
 duplicate.records.push(structuredClone(duplicate.records[0]));
 refresh(duplicate);
 await fail(()=>encryptVaultSubsetFile(duplicate,password));
});
test("media pointers reject even correctly rehashed source content",async()=>{
 const cases=[
  row=>{row.photo_1_id="eeeeeeee-2222-4333-8444-555555555555"},
  row=>{row.body="See /storage/v1/object/private/secret.jpg"},
  row=>{row.document_url="https://storage.example.com/secrets.pdf"},
  row=>{row.file_path="secret.docx"},
  row=>{row.body="data:image/png;base64,aGVsbG8="},
  row=>{row.source_url="https://example.org/old-document.pdf"},
  row=>{row.profile_photo_url="https://example.org/avatar"}
 ];
 for(const change of cases){
  const m=fixture();
  patch(m,m.records.findIndex(r=>r.source_table==="notes"),change);
  await fail(()=>encryptVaultSubsetFile(m,password));
 }
});
test("edited owner-bound manifest cannot be substituted by changing plaintext flags",async()=>{
 const m=fixture();
 m.all_69_types_packaged=true;
 await fail(()=>encryptVaultSubsetFile(m,password));
 const n=fixture();
 n.server_signed=true;
 await fail(()=>encryptVaultSubsetFile(n,password));
 const p=fixture();
 p.can_restore=true;
 await fail(()=>encryptVaultSubsetFile(p,password));
});
