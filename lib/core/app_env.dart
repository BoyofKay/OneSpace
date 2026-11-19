/// Which OneSpace backend this build talks to.
///
/// Two versions of the app exist side by side on a phone:
///  * QA         — package `onespace.qa`,        "OneSpace QA", the QA Supabase project (test data only).
///  * Production — package `live.onespace.app`,  "OneSpace",    the production Supabase project.
///
/// The build chooses one with `--dart-define=ONESPACE_ENV=qa|production`
/// (the Android flavor `qa` / `prod` sets the package name, label and icon).
/// Anything other than `production` is treated as QA, so a build can never
/// reach real couples' data by accident.
class OneSpaceEnv {
  const OneSpaceEnv._();

  static const name = String.fromEnvironment('ONESPACE_ENV', defaultValue: 'qa');
  static const isProduction = name == 'production';
  static const expectedAndroidPackage =
      isProduction ? 'live.onespace.app' : 'onespace.qa';

  /// Refuse a build whose Android package and Supabase target disagree.
  /// This prevents a QA-configured app from accidentally using the Production
  /// package ID, or vice versa. The check happens before Supabase.initialize.
  static bool packageMatchesEnvironment(String? package) =>
      (name == 'qa' || name == 'production') &&
      package == expectedAndroidPackage;

  // QA backend (the original OneSpace project; test users and demo data only).
  static const _qaUrl = 'https://ugwrpeduzyzrujkizqfo.supabase.co';
  static const _qaKey = 'sb_publishable_TtW_uUboFxD4adF5o7FSfA_cpjojMCe';

  // Production backend (OneSpace Production project, Frankfurt).
  static const _prodUrl = 'https://letcgxbnblohhfyeuigz.supabase.co';
  static const _prodKey = 'sb_publishable_eAeTViXIscberKyVhCQiWg_h3rivqwo';

  static const supabaseUrl = isProduction ? _prodUrl : _qaUrl;
  static const publishableKey = isProduction ? _prodKey : _qaKey;

  /// Native callback for email confirmation, password recovery and Google / Apple sign-in.
  /// Each must be listed in that project's Supabase Auth > URL Configuration > Redirect URLs.
  static const authRedirect = isProduction ? 'onespace://auth-callback/' : 'onespace-preview://auth-callback/';

  /// Shown in Support so testers can tell the two apps apart.
  static const label = isProduction ? 'OneSpace' : 'OneSpace QA';
}
