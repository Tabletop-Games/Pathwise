package com.shenmareparas.pathwise;

import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.SoundPool;
import android.net.Uri;
import android.os.Build;
import android.os.SystemClock;
import android.os.Vibrator;
import android.os.VibratorManager;
import android.net.ConnectivityManager;
import android.net.NetworkCapabilities;
import android.provider.Settings;
import android.view.HapticFeedbackConstants;
import android.view.View;
import androidx.annotation.NonNull;
import com.google.android.gms.games.PlayGames;
import com.google.android.gms.games.PlayGamesSdk;
import com.google.android.gms.games.achievement.Achievement;
import com.google.android.gms.games.achievement.AchievementBuffer;
import io.flutter.FlutterInjector;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.util.Base64;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class MainActivity extends FlutterActivity {
    private SoundPool soundPool;
    private final Map<String, Integer> soundIds = new HashMap<>();

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        CloudSaveChannel.register(engine, this);
        registerAudioChannel(engine);
        registerHapticsChannel(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "games.tabletop.pathwise/commerce").setMethodCallHandler((call, result) -> {
            if (!call.method.equals("verifyPlayPurchase")) {
                result.notImplemented();
                return;
            }
            String key = call.argument("key");
            String data = call.argument("data");
            String signature = call.argument("signature");
            if (key == null || data == null || signature == null) {
                result.success(false);
                return;
            }
            try {
                var spec = new X509EncodedKeySpec(Base64.decode(key, Base64.DEFAULT));
                var verifier = Signature.getInstance("SHA1withRSA");
                verifier.initVerify(KeyFactory.getInstance("RSA").generatePublic(spec));
                verifier.update(data.getBytes(StandardCharsets.UTF_8));
                result.success(verifier.verify(Base64.decode(signature, Base64.DEFAULT)));
            } catch (GeneralSecurityException | IllegalArgumentException error) {
                result.success(false);
            }
        });
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
                    case "submitScore":
                        String board = call.argument("id");
                        String score = call.argument("score");
                        if (board == null || board.isEmpty() || score == null ||
                                !score.matches("[1-9][0-9]{0,8}")) {
                            result.success(false);
                            break;
                        }
                        PlayGames.getLeaderboardsClient(this)
                                .submitScoreImmediate(board, Long.parseLong(score))
                                .addOnCompleteListener(task -> result.success(task.isSuccessful()));
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

    private void registerAudioChannel(@NonNull FlutterEngine engine) {
        ensureSoundPool();
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "games.tabletop.pathwise/audio").setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "preload":
                    List<String> assets = call.argument("assets");
                    if (assets != null) {
                        ensureSoundPool();
                        final var loader = FlutterInjector.instance().flutterLoader();
                        final File cacheDir = new File(getCacheDir(), "sfx");
                        if (!cacheDir.exists()) {
                            cacheDir.mkdirs();
                        }
                        for (String asset : assets) {
                            if (soundIds.containsKey(asset)) continue;
                            try {
                                String key = loader.getLookupKeyForAsset(asset);
                                File outFile = new File(cacheDir, new File(asset).getName());
                                if (!outFile.exists() || outFile.length() == 0) {
                                    try (InputStream in = getAssets().open(key);
                                         FileOutputStream out = new FileOutputStream(outFile)) {
                                        byte[] buf = new byte[4096];
                                        int read;
                                        while ((read = in.read(buf)) != -1) {
                                            out.write(buf, 0, read);
                                        }
                                    }
                                }
                                int id = soundPool.load(outFile.getAbsolutePath(), 1);
                                if (id != 0) {
                                    soundIds.put(asset, id);
                                }
                            } catch (IOException ignored) {
                            }
                        }
                    }
                    result.success(null);
                    break;
                case "play":
                    if (soundPool != null) {
                        String asset = call.argument("asset");
                        Double volArg = call.argument("volume");
                        Double rateArg = call.argument("rate");
                        Integer prioArg = call.argument("priority");
                        Integer id = asset == null ? null : soundIds.get(asset);
                        if (id != null) {
                            float vol = volArg == null ? 0.75f : volArg.floatValue();
                            float rate = rateArg == null ? 1.0f : rateArg.floatValue();
                            int prio = prioArg == null ? 1 : prioArg;
                            soundPool.play(id, vol, vol, prio, 0, rate);
                        }
                    }
                    result.success(null);
                    break;
                case "pauseAll":
                    if (soundPool != null) soundPool.autoPause();
                    result.success(null);
                    break;
                case "resumeAll":
                    if (soundPool != null) soundPool.autoResume();
                    result.success(null);
                    break;
                case "dispose":
                    if (soundPool != null) {
                        soundPool.release();
                        soundPool = null;
                        soundIds.clear();
                    }
                    result.success(null);
                    break;
                default:
                    result.notImplemented();
            }
        });
    }

    private void ensureSoundPool() {
        if (soundPool != null) return;
        AudioAttributes attrs = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_GAME)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        soundPool = new SoundPool.Builder()
                .setMaxStreams(4)
                .setAudioAttributes(attrs)
                .build();
    }

    private void registerHapticsChannel(@NonNull FlutterEngine engine) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(),
                "games.tabletop.pathwise/haptics").setMethodCallHandler((call, result) -> {
            if (!"trigger".equals(call.method)) {
                result.notImplemented();
                return;
            }
            if (!hasVibrator()) {
                result.success(false);
                return;
            }
            View view = getWindow() != null ? getWindow().getDecorView() : null;
            if (view == null) {
                result.success(false);
                return;
            }
            String kind = call.argument("kind");
            int constant = HapticFeedbackConstants.CLOCK_TICK;
            if ("light".equals(kind)) {
                constant = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
                        ? HapticFeedbackConstants.CONTEXT_CLICK
                        : HapticFeedbackConstants.KEYBOARD_TAP;
            } else if ("medium".equals(kind)) {
                constant = HapticFeedbackConstants.KEYBOARD_TAP;
            } else if ("heavy".equals(kind)) {
                constant = HapticFeedbackConstants.LONG_PRESS;
            } else if ("confirm".equals(kind)) {
                constant = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                        ? HapticFeedbackConstants.CONFIRM
                        : HapticFeedbackConstants.KEYBOARD_TAP;
            } else if ("reject".equals(kind)) {
                constant = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                        ? HapticFeedbackConstants.REJECT
                        : HapticFeedbackConstants.LONG_PRESS;
            }
            result.success(view.performHapticFeedback(constant));
        });
    }

    private boolean hasVibrator() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            VibratorManager vm = getSystemService(VibratorManager.class);
            return vm != null && vm.getDefaultVibrator().hasVibrator();
        }
        Vibrator v = getSystemService(Vibrator.class);
        return v != null && v.hasVibrator();
    }

    @Override
    protected void onPause() {
        if (soundPool != null) soundPool.autoPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (soundPool != null) soundPool.autoResume();
    }

    @Override
    protected void onDestroy() {
        if (soundPool != null) {
            soundPool.release();
            soundPool = null;
            soundIds.clear();
        }
        super.onDestroy();
    }
}
