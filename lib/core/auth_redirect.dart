import 'app_env.dart';

/// Native callback used for email confirmation, password recovery and social sign-in.
/// QA: onespace-preview://auth-callback/  ·  Production: onespace://auth-callback/
/// Add the matching URI to that project's Supabase Auth > URL Configuration > Redirect URLs.
const String oneSpaceAuthRedirectTo = OneSpaceEnv.authRedirect;
