package app.sinapsis

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/**
 * El servicio en primer plano de lo que suena (F47, paso 2b): una sola
 * `MediaSession` del sistema con su tarjeta en la barra de notificaciones y
 * en la pantalla de bloqueo, los botones de los auriculares y del reloj, el
 * foco de audio y los auriculares desconectados.
 *
 * Es de tipo «reproducción de medios», con el permiso que pide Android, y no
 * es el del trabajo largo ([LongWorkService], F21), que sigue aparte: cada
 * uno con su notificación y su canal.
 *
 * No hace sonar nada: suena Dart —la voz del teléfono, un audio—, en el
 * motor del proceso ([SinapsisEngine]). El servicio mantiene vivo el proceso
 * con la app minimizada o la pantalla apagada, y despierto mientras suena
 * —entre una oración y la siguiente el teléfono no se duerme—, y muestra lo
 * que Dart le dice. Lo que se toca vuelve a Dart por [MediaSessionChannel].
 *
 * Mientras suena, la tarjeta no se puede descartar; en pausa, sí, y
 * descartarla deja de leer. Al terminar, se va sola.
 */
class MediaPlaybackService : Service() {
    private lateinit var session: MediaSession
    private lateinit var audioManager: AudioManager

    /** Lo último que se mostró; `null` antes de la primera vez. */
    private var shown: MediaCard? = null
    private var inForeground = false

    private var focusRequest: AudioFocusRequest? = null
    private var hasFocus = false

    private var art: Bitmap? = null
    private var artFrom: ByteArray? = null

    private var wakeLock: PowerManager.WakeLock? = null

    private var noisyRegistered = false
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                MediaSessionChannel.interruption("noisy")
            }
        }
    }

    /**
     * Una llamada o el GPS hablando quitan el foco por un rato —y el lector,
     * que es voz, se pausa en vez de bajar el volumen—, otra app que empieza
     * a sonar se lo queda: Dart decide qué hacer con cada cosa.
     */
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                hasFocus = false
                MediaSessionChannel.interruption("lost")
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK,
            -> MediaSessionChannel.interruption("began")
            AudioManager.AUDIOFOCUS_GAIN -> MediaSessionChannel.interruption("ended")
        }
    }

    private val callback = object : MediaSession.Callback() {
        override fun onPlay() = MediaSessionChannel.command("play")
        override fun onPause() = MediaSessionChannel.command("pause")
        override fun onStop() = MediaSessionChannel.command("stop")
        override fun onSkipToNext() = MediaSessionChannel.command("next")
        override fun onFastForward() = MediaSessionChannel.command("skip", SKIP_MS)
        override fun onRewind() = MediaSessionChannel.command("skip", -SKIP_MS)
        override fun onSeekTo(pos: Long) = MediaSessionChannel.command("seek", pos)
        override fun onCustomAction(action: String, extras: Bundle?) {
            when (action) {
                CUSTOM_REWIND -> onRewind()
                CUSTOM_FORWARD -> onFastForward()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        session = MediaSession(this, TAG).apply {
            setCallback(callback)
            isActive = true
        }
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> MediaSessionChannel.command("play")
            ACTION_PAUSE -> MediaSessionChannel.command("pause")
            ACTION_REWIND -> MediaSessionChannel.command("skip", -SKIP_MS)
            ACTION_FORWARD -> MediaSessionChannel.command("skip", SKIP_MS)
            ACTION_NEXT -> MediaSessionChannel.command("next")
            ACTION_DISMISS -> MediaSessionChannel.command("stop")
        }
        // Arrancado para mostrar algo: tiene que pasar a primer plano ya.
        val card = pending
        if (card != null && !inForeground) render(card)
        if (pending == null && !inForeground) stopSelf()
        return START_NOT_STICKY
    }

    /** Muestra [card]: la sesión, la tarjeta, el primer plano, el foco y los auriculares. */
    fun render(card: MediaCard) {
        val previous = shown
        shown = card
        if (!card.artwork.contentEquals(artFrom)) {
            artFrom = card.artwork
            art = card.artwork?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        }
        if (previous == null || !card.looksLike(previous) || card.durationMs != previous.durationMs) {
            session.setMetadata(
                MediaMetadata.Builder()
                    .putString(MediaMetadata.METADATA_KEY_TITLE, card.title)
                    .putString(MediaMetadata.METADATA_KEY_ARTIST, card.subtitle)
                    .putLong(MediaMetadata.METADATA_KEY_DURATION, card.durationMs)
                    .apply { art?.let { putBitmap(MediaMetadata.METADATA_KEY_ART, it) } }
                    .build(),
            )
        }
        session.setPlaybackState(playbackState(card))

        if (card.playing) {
            if (card.focus) requestFocus() else abandonFocus()
            listenToNoisy(true)
            keepAwake(true)
        } else {
            listenToNoisy(false)
            keepAwake(false)
        }

        // La tarjeta se vuelve a armar solo si cambió algo que se ve: la
        // barra la adelanta el sistema con el estado de la sesión.
        if (previous != null && card.looksLike(previous) && inForeground == card.playing) return
        val notification = buildNotification(card)
        // Arrancado con `startForegroundService`, pasa a primer plano aunque
        // empiece en pausa —si no, Android corta la app—; en pausa se suelta
        // enseguida, y la tarjeta queda para descartar.
        if (card.playing || previous == null) {
            try {
                startInForeground(notification)
                inForeground = true
            } catch (e: RuntimeException) {
                // Android 12 en adelante no deja volver a primer plano desde
                // segundo plano fuera de sus excepciones —los botones de la
                // tarjeta y de los auriculares lo son—: la tarjeta se
                // actualiza igual.
                Log.w(TAG, "No se pudo pasar a primer plano", e)
            }
        }
        if (!card.playing && inForeground) {
            stopForeground(STOP_FOREGROUND_DETACH)
            inForeground = false
        }
        notificationManager().notify(NOTIFICATION_ID, notification)
    }

    /** Ya no suena nada: se va todo. */
    fun finish() {
        // Lo que se pida desde ahora es para un servicio nuevo: este se va.
        if (instance === this) instance = null
        abandonFocus()
        listenToNoisy(false)
        keepAwake(false)
        session.isActive = false
        stopForeground(STOP_FOREGROUND_REMOVE)
        notificationManager().cancel(NOTIFICATION_ID)
        inForeground = false
        stopSelf()
    }

    override fun onDestroy() {
        abandonFocus()
        listenToNoisy(false)
        keepAwake(false)
        session.release()
        if (instance === this) instance = null
        super.onDestroy()
    }

    private fun playbackState(card: MediaCard): PlaybackState {
        var actions = PlaybackState.ACTION_PLAY or
            PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_STOP or
            PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_FAST_FORWARD or
            PlaybackState.ACTION_REWIND
        if (card.hasNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        return PlaybackState.Builder()
            .setActions(actions)
            .setState(
                if (card.playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                card.positionMs,
                if (card.playing) 1f else 0f,
                SystemClock.elapsedRealtime(),
            )
            // Android 13 en adelante arma los botones de la tarjeta con esto:
            // −10 s y +10 s a los lados de reproducir.
            .addCustomAction(
                PlaybackState.CustomAction.Builder(
                    CUSTOM_REWIND,
                    getString(R.string.media_rewind),
                    android.R.drawable.ic_media_rew,
                ).build(),
            )
            .addCustomAction(
                PlaybackState.CustomAction.Builder(
                    CUSTOM_FORWARD,
                    getString(R.string.media_forward),
                    android.R.drawable.ic_media_ff,
                ).build(),
            )
            .build()
    }

    private fun buildNotification(card: MediaCard): Notification {
        ensureChannel()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java)
                .setAction(MediaSessionChannel.ACTION_OPEN)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(card.title)
            .setContentText(card.subtitle)
            .setContentIntent(open)
            .setDeleteIntent(serviceIntent(ACTION_DISMISS))
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(card.playing)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .addAction(action(android.R.drawable.ic_media_rew, R.string.media_rewind, ACTION_REWIND))
            .addAction(
                if (card.playing) {
                    action(android.R.drawable.ic_media_pause, R.string.media_pause, ACTION_PAUSE)
                } else {
                    action(android.R.drawable.ic_media_play, R.string.media_play, ACTION_PLAY)
                },
            )
            .addAction(action(android.R.drawable.ic_media_ff, R.string.media_forward, ACTION_FORWARD))
        if (card.hasNext) {
            builder.addAction(action(android.R.drawable.ic_media_next, R.string.media_next, ACTION_NEXT))
        }
        art?.let { builder.setLargeIcon(it) }
        builder.setStyle(
            Notification.MediaStyle()
                .setMediaSession(session.sessionToken)
                .setShowActionsInCompactView(0, 1, 2),
        )
        return builder.build()
    }

    private fun action(icon: Int, label: Int, action: String): Notification.Action =
        Notification.Action.Builder(
            Icon.createWithResource(this, icon),
            getString(label),
            serviceIntent(action),
        ).build()

    private fun serviceIntent(action: String): PendingIntent = PendingIntent.getService(
        this,
        action.hashCode(),
        Intent(this, MediaPlaybackService::class.java).setAction(action),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    private fun startInForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    /**
     * El foco de audio, para que una llamada lo pause: se pide una vez y se
     * guarda mientras haya tarjeta, también en pausa —si no, no llega el
     * aviso de que terminó la llamada y no se puede seguir solo—.
     */
    private fun requestFocus() {
        if (hasFocus) return
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build(),
                )
                // Es voz: con el GPS hablando se pausa en vez de bajar el
                // volumen, que taparía las dos.
                .setWillPauseWhenDucked(true)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
                .also { focusRequest = it }
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                focusListener,
                AudioManager.STREAM_MUSIC,
                AudioManager.AUDIOFOCUS_GAIN,
            )
        }
        hasFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun abandonFocus() {
        if (!hasFocus) return
        hasFocus = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(focusListener)
        }
    }

    private fun listenToNoisy(listen: Boolean) {
        if (listen == noisyRegistered) return
        noisyRegistered = listen
        if (!listen) {
            unregisterReceiver(noisy)
            return
        }
        val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(noisy, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(noisy, filter)
        }
    }

    /**
     * Despierto mientras suena: la voz del teléfono se pide oración por
     * oración, y con la pantalla apagada el teléfono se dormiría entre una y
     * otra. Se suelta en pausa y al terminar.
     */
    @SuppressLint("WakelockTimeout")
    private fun keepAwake(awake: Boolean) {
        val lock = wakeLock ?: (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sinapsis:media")
            .apply { setReferenceCounted(false) }
            .also { wakeLock = it }
        if (awake && !lock.isHeld) lock.acquire()
        if (!awake && lock.isHeld) lock.release()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = notificationManager()
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                getString(R.string.media_channel),
                // Baja: sin sonido ni vibración, como la de cualquier
                // reproductor de música.
                NotificationManager.IMPORTANCE_LOW,
            ).apply { setShowBadge(false) },
        )
    }

    private fun notificationManager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    companion object {
        private const val TAG = "MediaPlaybackService"
        private const val CHANNEL_ID = "lo_que_suena"
        private const val NOTIFICATION_ID = 47
        private const val SKIP_MS = 10_000L

        private const val ACTION_PLAY = "app.sinapsis.media.PLAY"
        private const val ACTION_PAUSE = "app.sinapsis.media.PAUSE"
        private const val ACTION_REWIND = "app.sinapsis.media.REWIND"
        private const val ACTION_FORWARD = "app.sinapsis.media.FORWARD"
        private const val ACTION_NEXT = "app.sinapsis.media.NEXT"
        private const val ACTION_DISMISS = "app.sinapsis.media.DISMISS"
        private const val CUSTOM_REWIND = "rewind10"
        private const val CUSTOM_FORWARD = "forward10"

        @Volatile private var instance: MediaPlaybackService? = null

        /** Lo último que pidió Dart, para el servicio que todavía está arrancando. */
        @Volatile private var pending: MediaCard? = null

        /** Muestra [card]: arranca el servicio la primera vez. */
        fun show(context: Context, card: MediaCard) {
            pending = card
            val running = instance
            if (running != null) {
                running.render(card)
                return
            }
            val intent = Intent(context, MediaPlaybackService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: RuntimeException) {
                // Pedido desde segundo plano, cuando Android ya no lo deja: lo
                // que suena sigue, sin la tarjeta.
                Log.w(TAG, "No se pudo arrancar el servicio", e)
            }
        }

        /** Ya no suena nada. */
        fun end() {
            pending = null
            instance?.finish()
        }
    }
}
