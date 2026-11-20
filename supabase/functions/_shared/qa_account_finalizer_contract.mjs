// Pure fail-closed gate for the STAGED QA Auth-admin account finalizer.
// This is not a user-facing endpoint and never enables deletion itself.
const UUID=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const ZERO_FIELDS=Object.freeze([
 "remaining_relationship_memberships","remaining_created_spaces",
 "legacy_couple_private_rows","unresolved_auth_user_fk_references",
 "remaining_storage_objects_owned","remaining_storage_folder_references",
 "unfinished_private_file_purges","unfinished_shared_file_purges",
]);
export function validAccountId(id){
 return typeof id==="string"&&UUID.test(id);
}
export function isAccountReadyForAuthDeletion(report){
 if(!report||typeof report!=="object")return false;
 if(report.ready_for_auth_delete!==true||report.due!==true||
    report.private_namespace_exists!==true)return false;
 return ZERO_FIELDS.every(k=>Object.hasOwn(report,k)&&
  typeof report[k]==="number"&&report[k]===0);
}
