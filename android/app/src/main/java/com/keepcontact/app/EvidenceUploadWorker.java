package com.keepcontact.app;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.work.BackoffPolicy;
import androidx.work.Constraints;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import java.util.concurrent.TimeUnit;

/** Independent from fresh observations: a quiet phone still retries queued evidence. */
public final class EvidenceUploadWorker extends Worker {
    private static final String WORK_NAME = "kc-passive-evidence-upload";

    public EvidenceUploadWorker(@NonNull Context context, @NonNull WorkerParameters parameters) {
        super(context, parameters);
    }

    static void schedule(Context context) {
        if (!PassivePing.isEvidenceConfigured(context) && PushBindingStore.pendingRevocations(context).length() == 0) return;
        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(EvidenceUploadWorker.class)
            .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build();
        // Appending closes the KEEP race when an observation is enqueued just
        // after a running worker has read an empty queue but before it exits.
        WorkManager.getInstance(context.getApplicationContext())
            .enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request);
    }

    @NonNull @Override public Result doWork() {
        boolean revocationsDone = PushBindingStore.drainRevocations(getApplicationContext());
        boolean evidenceDone = PassivePing.drainEvidenceQueue(getApplicationContext());
        return revocationsDone && evidenceDone ? Result.success() : Result.retry();
    }
}
