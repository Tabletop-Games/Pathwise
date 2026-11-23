package games.tabletop.pathwise;

import android.os.SystemClock;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.provider.Settings;
import androidx.annotation.NonNull;
import com.google.android.gms.games.PlayGames;
import com.google.android.gms.games.PlayGamesSdk;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.Arrays;

public class MainActivity extends FlutterActivity {
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "games.tabletop.pathwise/games").setMethodCallHandler((call, result) -> {
            if (getString(R.string.pathwise_games_project).equals("0")) {
                result.error("games_disabled", "Play Games is disabled in this build.", null);
                return;
            }
            try {
                PlayGamesSdk.initialize(this);
                var auth = PlayGames.getGamesSignInClient(this);
                switch (call.method) {
                    case "status":
                        auth.isAuthenticated().addOnCompleteListener(task -> result.success(
                                task.isSuccessful() && task.getResult().isAuthenticated()));
                        break;
                    case "signIn":
                        auth.signIn().addOnCompleteListener(task -> result.success(
                                task.isSuccessful() && task.getResult().isAuthenticated()));
                        break;
                    case "achievements":
                        PlayGames.getAchievementsClient(this).getAchievementsIntent()
                                .addOnCompleteListener(task -> {
                                    if (task.isSuccessful()) startActivityForResult(task.getResult(), 923);
                                    result.success(task.isSuccessful());
                                });
                        break;
                    case "leaderboard":
                        String id = call.argument("id");
                        if (id == null || id.isEmpty()) {
                            result.success(false);
                            break;
                        }
                        PlayGames.getLeaderboardsClient(this).getLeaderboardIntent(id)
                                .addOnCompleteListener(task -> {
                                    if (task.isSuccessful()) startActivityForResult(task.getResult(), 924);
                                    result.success(task.isSuccessful());
                                });
                        break;
                    case "unlock":
                        String achievement = call.argument("id");
                        if (achievement == null || achievement.isEmpty()) {
                            result.success(false);
                            break;
                        }
                        PlayGames.getAchievementsClient(this).unlockImmediate(achievement)
                                .addOnCompleteListener(task -> result.success(task.isSuccessful()));
                        break;
                    case "serverCode":
                        String client = call.argument("client");
                        if (client == null || !client.endsWith(".apps.googleusercontent.com")) {
                            result.success(null);
                            break;
                        }
                        auth.requestServerSideAccess(client, false)
                                .addOnCompleteListener(task -> result.success(
                                        task.isSuccessful() ? task.getResult() : null));
                        break;
                    default:
                        result.notImplemented();
                }
            } catch (RuntimeException error) {
                result.error("games_unavailable", "Play Games could not be opened.", null);
            }
        });
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
