package com.shenmareparas.pathwise;

import android.app.Activity;
import androidx.annotation.NonNull;
import com.google.android.gms.games.PlayGames;
import com.google.android.gms.games.PlayGamesSdk;
import com.google.android.gms.games.SnapshotsClient;
import com.google.android.gms.games.snapshot.Snapshot;
import com.google.android.gms.games.snapshot.SnapshotMetadataChange;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Play Games Services Saved Games for the Flutter cloud save layer.
 *
 * Reads and writes always open the snapshot with RESOLUTION_POLICY_MANUAL, so
 * a concurrent write from another device surfaces as a conflict. Dart decides
 * the outcome and calls "resolve". Nothing is merged or discarded here.
 *
 * Methods (Dart side: lib/cloud/cloud_save_provider.dart):
 *   status            -> {signedIn, playerId?}
 *   signIn            -> {signedIn, playerId?}; error auth_failed on failure
 *   signOut           -> null
 *   fetch {name}      -> {bytes} or {conflictId, conflictRemote, conflictLocal}
 *   commit {name, bytes, description}
 *                     -> {committed: true} or {committed: false, conflictId, conflictRemote}
 *   resolve {conflictId, bytes} -> null
 *
 * Errors use code "unavailable" for service or network problems.
 */
final class CloudSaveChannel implements MethodChannel.MethodCallHandler {
    static final String CHANNEL = "games.tabletop.pathwise/cloud";

    private final Activity activity;
    private final Map<String, SnapshotsClient.SnapshotConflict> conflicts = new HashMap<>();

    private CloudSaveChannel(Activity activity) {
        this.activity = activity;
    }

    static void register(FlutterEngine engine, Activity activity) {
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler(new CloudSaveChannel(activity));
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (activity.getString(R.string.pathwise_games_project).equals("0")) {
            result.error("unavailable", "Play Games is not configured in this build.", null);
            return;
        }
        try {
            PlayGamesSdk.initialize(activity);
            switch (call.method) {
                case "status":
                    status(result);
                    break;
                case "signIn":
                    signIn(result);
                    break;
                case "signOut":
                    PlayGames.getGamesSignInClient(activity).signOut()
                            .addOnCompleteListener(task -> result.success(null));
                    break;
                case "fetch":
                    fetch(call.argument("name"), result);
                    break;
                case "commit":
                    commit(call.argument("name"), call.argument("bytes"),
                            call.argument("description"), result);
                    break;
                case "resolve":
                    resolve(call.argument("conflictId"), call.argument("bytes"), result);
                    break;
                default:
                    result.notImplemented();
            }
        } catch (RuntimeException error) {
            result.error("unavailable", "Play Games could not be opened.", null);
        }
    }

    private void status(MethodChannel.Result result) {
        PlayGames.getGamesSignInClient(activity).isAuthenticated().addOnCompleteListener(task -> {
            if (!task.isSuccessful() || !task.getResult().isAuthenticated()) {
                result.success(signedOut());
                return;
            }
            playerId(result);
        });
    }

    private void signIn(MethodChannel.Result result) {
        PlayGames.getGamesSignInClient(activity).signIn().addOnCompleteListener(task -> {
            if (!task.isSuccessful()) {
                result.error("auth_failed", "Sign-in did not complete.", null);
                return;
            }
            if (!task.getResult().isAuthenticated()) {
                result.success(signedOut());
                return;
            }
            playerId(result);
        });
    }

    private void playerId(MethodChannel.Result result) {
        PlayGames.getPlayersClient(activity).getCurrentPlayerId().addOnCompleteListener(task -> {
            if (!task.isSuccessful() || task.getResult() == null) {
                result.error("unavailable", "The player is unavailable.", null);
                return;
            }
            Map<String, Object> reply = new HashMap<>();
            reply.put("signedIn", true);
            reply.put("playerId", task.getResult());
            result.success(reply);
        });
    }

    private static Map<String, Object> signedOut() {
        Map<String, Object> reply = new HashMap<>();
        reply.put("signedIn", false);
        return reply;
    }

    private void fetch(String name, MethodChannel.Result result) {
        if (name == null || name.isEmpty()) {
            result.error("unavailable", "Missing save name.", null);
            return;
        }
        SnapshotsClient client = PlayGames.getSnapshotsClient(activity);
        client.open(name, true, SnapshotsClient.RESOLUTION_POLICY_MANUAL)
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful() || task.getResult() == null) {
                        result.error("unavailable", "The saved game could not be opened.", null);
                        return;
                    }
                    SnapshotsClient.DataOrConflict<Snapshot> opened = task.getResult();
                    if (opened.isConflict()) {
                        result.success(conflictReply(opened.getConflict(), true));
                        return;
                    }
                    Snapshot snapshot = opened.getData();
                    try {
                        byte[] bytes = snapshot.getSnapshotContents().readFully();
                        Map<String, Object> reply = new HashMap<>();
                        reply.put("bytes", bytes);
                        result.success(reply);
                    } catch (IOException error) {
                        result.error("unavailable", "The saved game could not be read.", null);
                    } finally {
                        client.discardAndClose(snapshot);
                    }
                });
    }

    private void commit(String name, byte[] bytes, String description, MethodChannel.Result result) {
        if (name == null || bytes == null) {
            result.error("unavailable", "Missing save data.", null);
            return;
        }
        SnapshotsClient client = PlayGames.getSnapshotsClient(activity);
        client.open(name, true, SnapshotsClient.RESOLUTION_POLICY_MANUAL)
                .addOnCompleteListener(task -> {
                    if (!task.isSuccessful() || task.getResult() == null) {
                        result.error("unavailable", "The saved game could not be opened.", null);
                        return;
                    }
                    SnapshotsClient.DataOrConflict<Snapshot> opened = task.getResult();
                    if (opened.isConflict()) {
                        result.success(conflictReply(opened.getConflict(), false));
                        return;
                    }
                    Snapshot snapshot = opened.getData();
                    try {
                        snapshot.getSnapshotContents().writeBytes(bytes);
                    } catch (RuntimeException error) {
                        client.discardAndClose(snapshot);
                        result.error("unavailable", "The save could not be written.", null);
                        return;
                    }
                    SnapshotMetadataChange change = new SnapshotMetadataChange.Builder()
                            .setDescription(description == null ? "Pathwise progress" : description)
                            .build();
                    client.commitAndClose(snapshot, change).addOnCompleteListener(commitTask -> {
                        if (!commitTask.isSuccessful()) {
                            result.error("unavailable", "The save could not be uploaded.", null);
                            return;
                        }
                        Map<String, Object> reply = new HashMap<>();
                        reply.put("committed", true);
                        result.success(reply);
                    });
                });
    }

    private void resolve(String conflictId, byte[] bytes, MethodChannel.Result result) {
        SnapshotsClient.SnapshotConflict conflict = conflictId == null ? null : conflicts.remove(conflictId);
        if (conflict == null || bytes == null) {
            result.error("unavailable", "That conflict is no longer open.", null);
            return;
        }
        Snapshot local = conflict.getSnapshot();
        try {
            local.getSnapshotContents().writeBytes(bytes);
        } catch (RuntimeException error) {
            result.error("unavailable", "The resolution could not be written.", null);
            return;
        }
        SnapshotMetadataChange change = new SnapshotMetadataChange.Builder()
                .setDescription("Pathwise progress")
                .build();
        PlayGames.getSnapshotsClient(activity)
                .resolveConflict(conflict.getConflictId(), local.getMetadata().getSnapshotId(),
                        change, local.getSnapshotContents())
                .addOnCompleteListener(task -> {
                    if (task.isSuccessful()) {
                        result.success(null);
                    } else {
                        result.error("unavailable", "The conflict could not be resolved.", null);
                    }
                });
    }

    /**
     * Keeps the conflict open for a later "resolve". Returns both copies so
     * Dart can summarise them. [reading] is true for fetch, false for commit.
     */
    private Map<String, Object> conflictReply(SnapshotsClient.SnapshotConflict conflict, boolean reading) {
        String id = conflict.getConflictId() != null ? conflict.getConflictId() : UUID.randomUUID().toString();
        conflicts.put(id, conflict);
        Map<String, Object> reply = new HashMap<>();
        reply.put("committed", false);
        reply.put("conflictId", id);
        reply.put("conflictLocal", contents(conflict.getSnapshot()));
        reply.put("conflictRemote", contents(conflict.getConflictingSnapshot()));
        reply.put("reading", reading);
        return reply;
    }

    private static byte[] contents(Snapshot snapshot) {
        if (snapshot == null) return new byte[0];
        try {
            return snapshot.getSnapshotContents().readFully();
        } catch (IOException error) {
            return new byte[0];
        }
    }
}
