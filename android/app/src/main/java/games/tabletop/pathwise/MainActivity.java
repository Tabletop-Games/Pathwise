package games.tabletop.pathwise;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.SystemClock;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.provider.Settings;
import androidx.annotation.NonNull;
import com.google.android.gms.games.PlayGames;
import com.google.android.gms.games.PlayGamesSdk;
import com.google.android.gms.games.achievement.Achievement;
import com.google.android.gms.games.achievement.AchievementBuffer;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;

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
                                    result.success(task.isSuccessful() && openGamesScreen(task.getResult(), 923));
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
                                    result.success(task.isSuccessful() && openGamesScreen(task.getResult(), 924));
                                });
                        break;
                    case "loadAchievements":
                        loadAchievements(result);
                        break;
                    case "updateAchievement":
                        updateAchievement(call.argument("player"), call.argument("id"),
                                call.argument("steps"), result);
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
                "games.tabletop.pathwise/share").setMethodCallHandler((call, result) -> {
            final String content = call.argument("content");
            if (content == null || content.isEmpty()) {
                result.success(false);
                return;
            }
            switch (call.method) {
                case "chooser":
                    result.success(open(Intent.createChooser(textIntent(content), "Share your result")));
                    break;
                case "whatsapp":
                    result.success(open(textIntent(content).setPackage("com.whatsapp")) ||
                            open(textIntent(content).setPackage("com.whatsapp.w4b")));
                    break;
                case "web":
                    final Uri uri = Uri.parse(content);
                    result.success("https".equals(uri.getScheme()) &&
                            open(new Intent(Intent.ACTION_VIEW, uri)));
                    break;
                default:
                    result.notImplemented();
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

    private Intent textIntent(String text) {
        return new Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, text);
    }

    private boolean open(Intent intent) {
        try {
            startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException error) {
            return false;
        }
    }

    private boolean openGamesScreen(Intent intent, int request) {
        try {
            startActivityForResult(intent, request);
            return true;
        } catch (ActivityNotFoundException | SecurityException error) {
            return false;
        }
    }

    private void loadAchievements(MethodChannel.Result result) {
        final var players = PlayGames.getPlayersClient(this);
        players.getCurrentPlayerId().addOnCompleteListener(player -> {
            if (!player.isSuccessful() || player.getResult() == null) {
                result.success(null);
                return;
            }
            PlayGames.getAchievementsClient(this).load(true).addOnCompleteListener(load -> {
                if (!load.isSuccessful() || load.getResult() == null) {
                    result.success(null);
                    return;
                }
                final Map<String, Object> progress = new HashMap<>();
                try (AchievementBuffer buffer = load.getResult().get()) {
                    if (buffer == null || load.getResult().isStale()) {
                        result.success(null);
                        return;
                    }
                    for (Achievement item : buffer) {
                        final boolean incremental = item.getType() == Achievement.TYPE_INCREMENTAL;
                        progress.put(item.getAchievementId(), Arrays.asList(
                                incremental ? item.getCurrentSteps() : 0,
                                incremental ? item.getTotalSteps() : 0,
                                item.getState() == Achievement.STATE_UNLOCKED));
                    }
                }
                final Map<String, Object> state = new HashMap<>();
                state.put("player", player.getResult());
                state.put("progress", progress);
                players.getCurrentPlayerId().addOnCompleteListener(current -> result.success(
                        current.isSuccessful() && player.getResult().equals(current.getResult())
                                ? state : null));
            });
        });
    }

    private void updateAchievement(String player, String id, String steps,
                                   MethodChannel.Result result) {
        if (player == null || id == null || id.isEmpty() ||
                (steps != null && !steps.matches("[1-9][0-9]{0,4}"))) {
            result.success(false);
            return;
        }
        PlayGames.getPlayersClient(this).getCurrentPlayerId().addOnCompleteListener(current -> {
            if (!current.isSuccessful() || !player.equals(current.getResult())) {
                result.success(false);
                return;
            }
            final var achievements = PlayGames.getAchievementsClient(this);
            final var update = steps == null ? achievements.unlockImmediate(id)
                    : achievements.setStepsImmediate(id, Integer.parseInt(steps));
            update.addOnCompleteListener(task -> result.success(task.isSuccessful()));
        });
    }
}
