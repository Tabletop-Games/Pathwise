package games.tabletop.pathwise;

import android.os.SystemClock;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.provider.Settings;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.Arrays;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "games.tabletop.pathwise/clock").setMethodCallHandler((call, result) -> {
            if (call.method.equals("online")) {
                ConnectivityManager manager = getSystemService(ConnectivityManager.class);
                NetworkCapabilities network = manager == null ? null :
                        manager.getNetworkCapabilities(manager.getActiveNetwork());
                result.success(network != null &&
                        network.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
                return;
            }
            if (!call.method.equals("bootTime")) {
                result.notImplemented();
                return;
            }
            int boot = Settings.Global.getInt(getContentResolver(), "boot_count", -1);
            result.success(Arrays.asList(boot, SystemClock.elapsedRealtime()));
        });
    }
}
