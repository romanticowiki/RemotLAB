package mx.uteq.aula_remota

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity y no FlutterActivity: el BiometricPrompt de Android
// es un DialogFragment y necesita un FragmentManager. Con FlutterActivity a
// secas, local_auth lanza "no_fragment_activity" y el desbloqueo nunca aparece.
class MainActivity : FlutterFragmentActivity()
