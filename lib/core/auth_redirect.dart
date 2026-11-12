/// Preview-only native callback used for email confirmation and password recovery.
/// Add this exact URI to Supabase Auth > URL Configuration > Redirect URLs.
/// Production builds must use a separate verified callback.
const String oneSpaceAuthRedirectTo = 'onespace-preview://auth-callback/';
