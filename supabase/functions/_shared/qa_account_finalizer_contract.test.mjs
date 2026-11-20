import test from "node:test";
import assert from "node:assert/strict";
import {validAccountId,isAccountReadyForAuthDeletion} from "./qa_account_finalizer_contract.mjs";
const clean=()=>({
 ready_for_auth_delete:true,due:true,private_namespace_exists:true,
 remaining_relationship_memberships:0,remaining_created_spaces:0,
 legacy_couple_private_rows:0,unresolved_auth_user_fk_references:0,
 remaining_storage_objects_owned:0,remaining_storage_folder_references:0,
 unfinished_private_file_purges:0,unfinished_shared_file_purges:0,
 remaining_shared_storage_objects:0,
});
test("Only real UUIDs are eligible for the server account-deletion API",()=>{
 assert.equal(validAccountId("a1111111-1111-4111-8111-111111111111"),true);
 for(const v of [null,0,{},'','not-a-uuid','../users','00000000-0000-0000-0000-000000000000']){
  assert.equal(validAccountId(v),false);
 }
});
test("Complete clean due account is eligible, no field may be omitted",()=>{
 assert.equal(isAccountReadyForAuthDeletion(clean()),true);
 for(const key of Object.keys(clean())){
  const x=clean();delete x[key];
  assert.equal(isAccountReadyForAuthDeletion(x),false,key);
 }
});
test("One live pair, user-owned file, personal queue or missing due state blocks deletion",()=>{
 for(const key of [
  "remaining_relationship_memberships","remaining_created_spaces",
  "legacy_couple_private_rows","unresolved_auth_user_fk_references",
  "remaining_storage_objects_owned","remaining_storage_folder_references",
  "unfinished_private_file_purges","unfinished_shared_file_purges",
  "remaining_shared_storage_objects"
 ]){
  const x=clean();x[key]=1;
  assert.equal(isAccountReadyForAuthDeletion(x),false,key);
 }
 for(const [key,value] of [
  ["ready_for_auth_delete",false],["due",false],
  ["private_namespace_exists",false],
  ["remaining_storage_objects_owned","0"],
  ["unfinished_shared_file_purges",null],
 ]){
  const x=clean();x[key]=value;
  assert.equal(isAccountReadyForAuthDeletion(x),false,key);
 }
 assert.equal(isAccountReadyForAuthDeletion(null),false);
});
