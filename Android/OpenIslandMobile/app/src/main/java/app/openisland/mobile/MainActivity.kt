package app.openisland.mobile

import android.content.Context
import android.content.SharedPreferences
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.sse.EventSource
import okhttp3.sse.EventSourceListener
import okhttp3.sse.EventSources
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.InetAddress

data class MobileSession(
    val id: String,
    val title: String,
    val tool: String,
    val phase: String,
    val status: String,
    val workspace: String?,
    val workingDirectory: String?,
    val summary: String,
    val updatedAt: String,
    val canReply: Boolean,
    val unreadCompletion: Boolean,
)

data class MobileContextItem(
    val role: String,
    val text: String,
    val timestamp: String?,
)

data class MobileDetail(
    val session: MobileSession,
    val context: List<MobileContextItem>,
)

data class OpenIslandService(
    val name: String,
    val host: String,
    val port: Int,
) {
    val endpoint: String = "http://$host:$port"
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(colorScheme = darkOpenIslandColors()) {
                OpenIslandMobileApp(this)
            }
        }
    }
}

@Composable
private fun darkOpenIslandColors() = androidx.compose.material3.darkColorScheme(
    background = Color(0xFF050505),
    surface = Color(0xFF111111),
    primary = Color(0xFF6E9FFF),
    secondary = Color(0xFF42E86B),
)

@Composable
fun OpenIslandMobileApp(context: Context) {
    val prefs = remember { context.getSharedPreferences("open-island-mobile", Context.MODE_PRIVATE) }
    val client = remember { MobileRelayClient(prefs) }
    val discovery = remember { OpenIslandDiscovery(context) }
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current

    var endpoint by remember { mutableStateOf(prefs.getString("endpoint", "") ?: "") }
    var token by remember { mutableStateOf(prefs.getString("token", "") ?: "") }
    var pairingCode by remember { mutableStateOf("") }
    var statusText by remember { mutableStateOf("Mobile Relay is off until you pair with your Mac.") }
    var selectedSessionID by remember { mutableStateOf<String?>(null) }
    var detail by remember { mutableStateOf<MobileDetail?>(null) }
    val sessions = remember { mutableStateListOf<MobileSession>() }
    val services = remember { mutableStateListOf<OpenIslandService>() }

    fun refreshSessions() {
        if (endpoint.isBlank() || token.isBlank()) return
        scope.launch {
            runCatching { withContext(Dispatchers.IO) { client.fetchSessions(endpoint, token) } }
                .onSuccess { fetched ->
                    sessions.clear()
                    sessions.addAll(fetched)
                    statusText = "Connected"
                }
                .onFailure { statusText = it.message ?: "Failed to refresh sessions" }
        }
    }

    fun connectEvents() {
        if (endpoint.isBlank() || token.isBlank()) return
        client.connectEvents(endpoint, token) {
            refreshSessions()
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_START -> {
                    refreshSessions()
                    connectEvents()
                }
                Lifecycle.Event.ON_STOP -> client.disconnectEvents()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            client.disconnectEvents()
            discovery.stop()
        }
    }

    LaunchedEffect(Unit) {
        discovery.start(
            onFound = { service ->
                if (services.none { it.endpoint == service.endpoint }) {
                    services.add(service)
                    statusText = "Found ${service.name}"
                }
            },
            onError = { statusText = it }
        )
        refreshSessions()
        connectEvents()
    }

    Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFF050505)) {
        if (endpoint.isBlank() || token.isBlank()) {
            PairingScreen(
                services = services,
                endpoint = endpoint,
                pairingCode = pairingCode,
                statusText = statusText,
                onEndpointChange = { endpoint = it },
                onCodeChange = { pairingCode = it },
                onServiceSelected = { endpoint = it.endpoint },
                onPair = {
                    scope.launch {
                        val result = runCatching {
                            withContext(Dispatchers.IO) { client.pair(endpoint.trim(), pairingCode.trim()) }
                        }
                        result.onSuccess { newToken ->
                            token = newToken
                            prefs.edit()
                                .putString("endpoint", endpoint.trim())
                                .putString("token", newToken)
                                .apply()
                            statusText = "Paired"
                            refreshSessions()
                            connectEvents()
                        }.onFailure {
                            statusText = it.message ?: "Pairing failed"
                        }
                    }
                }
            )
        } else {
            MainScreen(
                endpoint = endpoint,
                statusText = statusText,
                sessions = sessions,
                selectedSessionID = selectedSessionID,
                detail = detail,
                onRefresh = { refreshSessions() },
                onDisconnect = {
                    client.disconnectEvents()
                    prefs.edit().clear().apply()
                    endpoint = ""
                    token = ""
                    sessions.clear()
                    detail = null
                    selectedSessionID = null
                    statusText = "Disconnected"
                },
                onSelect = { session ->
                    selectedSessionID = session.id
                    detail = null
                    scope.launch {
                        runCatching { withContext(Dispatchers.IO) { client.fetchDetail(endpoint, token, session.id) } }
                            .onSuccess {
                                detail = it
                                if (it.session.unreadCompletion) {
                                    scope.launch {
                                        withContext(Dispatchers.IO) {
                                            runCatching { client.markRead(endpoint, token, session.id) }
                                        }
                                        refreshSessions()
                                    }
                                }
                            }
                            .onFailure { statusText = it.message ?: "Failed to load detail" }
                    }
                },
                onBack = {
                    selectedSessionID = null
                    detail = null
                },
                onReply = { sessionID, text ->
                    scope.launch {
                        val result = runCatching {
                            withContext(Dispatchers.IO) { client.reply(endpoint, token, sessionID, text) }
                        }
                        result
                            .onSuccess { statusText = it }
                            .onFailure { statusText = it.message ?: "Reply failed" }
                        delay(600)
                        refreshSessions()
                    }
                }
            )
        }
    }
}

@Composable
private fun PairingScreen(
    services: List<OpenIslandService>,
    endpoint: String,
    pairingCode: String,
    statusText: String,
    onEndpointChange: (String) -> Unit,
    onCodeChange: (String) -> Unit,
    onServiceSelected: (OpenIslandService) -> Unit,
    onPair: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Text("Open Island", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(statusText, color = Color.White.copy(alpha = 0.62f))
        if (services.isNotEmpty()) {
            Text("Discovered Macs", color = Color.White.copy(alpha = 0.72f), fontWeight = FontWeight.SemiBold)
            services.forEach { service ->
                Card(
                    colors = CardDefaults.cardColors(containerColor = Color(0xFF151515)),
                    modifier = Modifier.fillMaxWidth().clickable { onServiceSelected(service) }
                ) {
                    Column(Modifier.padding(14.dp)) {
                        Text(service.name, fontWeight = FontWeight.SemiBold)
                        Text(service.endpoint, color = Color.White.copy(alpha = 0.5f))
                    }
                }
            }
        }
        OutlinedTextField(
            value = endpoint,
            onValueChange = onEndpointChange,
            label = { Text("Mac endpoint") },
            placeholder = { Text("http://192.168.1.20:12345") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        OutlinedTextField(
            value = pairingCode,
            onValueChange = onCodeChange,
            label = { Text("Pairing code") },
            modifier = Modifier.fillMaxWidth(),
            singleLine = true
        )
        Button(onClick = onPair, enabled = endpoint.isNotBlank() && pairingCode.length >= 4) {
            Text("Pair")
        }
    }
}

@Composable
private fun MainScreen(
    endpoint: String,
    statusText: String,
    sessions: List<MobileSession>,
    selectedSessionID: String?,
    detail: MobileDetail?,
    onRefresh: () -> Unit,
    onDisconnect: () -> Unit,
    onSelect: (MobileSession) -> Unit,
    onBack: () -> Unit,
    onReply: (String, String) -> Unit,
) {
    Column(Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("Open Island", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(endpoint, color = Color.White.copy(alpha = 0.45f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(statusText, color = Color.White.copy(alpha = 0.62f), maxLines = 1)
            }
            Button(onClick = onRefresh) { Text("Refresh") }
            Spacer(Modifier.width(8.dp))
            Button(onClick = onDisconnect, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333333))) {
                Text("Disconnect")
            }
        }

        if (selectedSessionID == null) {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(sessions, key = { it.id }) { session ->
                    SessionCard(session, onClick = { onSelect(session) })
                }
            }
        } else {
            DetailPane(detail = detail, onBack = onBack, onReply = onReply)
        }
    }
}

@Composable
private fun SessionCard(session: MobileSession, onClick: () -> Unit) {
    Card(
        shape = RoundedCornerShape(10.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF111111)),
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick)
    ) {
        Row(Modifier.padding(14.dp), verticalAlignment = Alignment.Top) {
            Box(
                Modifier
                    .padding(top = 5.dp)
                    .size(10.dp)
                    .background(statusColor(session), CircleShape)
            )
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(session.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (session.unreadCompletion) {
                        Spacer(Modifier.width(8.dp))
                        Text("NEW", color = Color(0xFF42E86B), style = MaterialTheme.typography.labelSmall)
                    }
                }
                Text("${session.tool} · ${session.status}", color = Color.White.copy(alpha = 0.58f))
                Text(session.summary, color = Color.White.copy(alpha = 0.76f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun DetailPane(
    detail: MobileDetail?,
    onBack: () -> Unit,
    onReply: (String, String) -> Unit,
) {
    var replyText by remember { mutableStateOf("") }
    if (detail == null) {
        Text("Loading…", color = Color.White.copy(alpha = 0.65f))
        return
    }

    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxSize()) {
        item {
            Button(onClick = onBack, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF333333))) {
                Text("Back")
            }
            Spacer(Modifier.height(8.dp))
            Text(detail.session.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
            Text(detail.session.summary, color = Color.White.copy(alpha = 0.72f))
        }
        items(detail.context) { item ->
            Card(colors = CardDefaults.cardColors(containerColor = Color(0xFF151515))) {
                Column(Modifier.padding(12.dp)) {
                    Text(item.role.uppercase(), color = Color.White.copy(alpha = 0.45f), style = MaterialTheme.typography.labelSmall)
                    Text(item.text, color = Color.White.copy(alpha = 0.86f))
                }
            }
        }
        item {
            if (detail.session.canReply) {
                OutlinedTextField(
                    value = replyText,
                    onValueChange = { replyText = it },
                    label = { Text("Reply") },
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 2,
                )
                Spacer(Modifier.height(8.dp))
                Button(
                    onClick = {
                        val text = replyText.trim()
                        if (text.isNotEmpty()) {
                            replyText = ""
                            onReply(detail.session.id, text)
                        }
                    },
                    enabled = replyText.isNotBlank()
                ) {
                    Text("Send")
                }
            } else {
                Text("Replies are unavailable for this session.", color = Color.White.copy(alpha = 0.5f))
            }
        }
    }
}

private fun statusColor(session: MobileSession): Color {
    return when {
        session.status.contains("Approval", ignoreCase = true) -> Color(0xFFFFB547)
        session.status.contains("Input", ignoreCase = true) -> Color(0xFFFFD95A)
        session.phase == "running" -> Color(0xFF6E9FFF)
        session.phase == "completed" && session.unreadCompletion -> Color(0xFF42E86B)
        session.phase == "completed" -> Color(0xFF6AA87F)
        else -> Color(0xFF777777)
    }
}

class MobileRelayClient(private val prefs: SharedPreferences) {
    private val http = OkHttpClient()
    private var eventSource: EventSource? = null

    fun pair(endpoint: String, code: String): String {
        val body = JSONObject().put("code", code).toString()
            .toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url("$endpoint/pair")
            .post(body)
            .build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Pairing failed: HTTP ${response.code}")
            return JSONObject(response.body?.string().orEmpty()).getString("token")
        }
    }

    fun fetchSessions(endpoint: String, token: String): List<MobileSession> {
        val request = authed("$endpoint/sessions", token).get().build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Sessions failed: HTTP ${response.code}")
            val root = JSONObject(response.body?.string().orEmpty())
            return root.getJSONArray("sessions").toSessions()
        }
    }

    fun fetchDetail(endpoint: String, token: String, sessionID: String): MobileDetail {
        val request = authed("$endpoint/sessions/${sessionID.urlPath()}", token).get().build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("Detail failed: HTTP ${response.code}")
            return JSONObject(response.body?.string().orEmpty()).toDetail()
        }
    }

    fun reply(endpoint: String, token: String, sessionID: String, text: String): String {
        val body = JSONObject().put("text", text).toString()
            .toRequestBody("application/json".toMediaType())
        val request = authed("$endpoint/sessions/${sessionID.urlPath()}/reply", token).post(body).build()
        http.newCall(request).execute().use { response ->
            val root = JSONObject(response.body?.string().orEmpty())
            if (!response.isSuccessful) error(root.optString("message", "Reply failed: HTTP ${response.code}"))
            return root.optString("message", "sent")
        }
    }

    fun markRead(endpoint: String, token: String, sessionID: String) {
        val request = authed("$endpoint/sessions/${sessionID.urlPath()}/mark-read", token)
            .post(ByteArray(0).toRequestBody(null))
            .build()
        http.newCall(request).execute().close()
    }

    fun connectEvents(endpoint: String, token: String, onEvent: () -> Unit) {
        disconnectEvents()
        val request = authed("$endpoint/events", token).get().build()
        eventSource = EventSources.createFactory(http).newEventSource(
            request,
            object : EventSourceListener() {
                override fun onEvent(eventSource: EventSource, id: String?, type: String?, data: String) {
                    onEvent()
                }
            }
        )
    }

    fun disconnectEvents() {
        eventSource?.cancel()
        eventSource = null
    }

    private fun authed(url: String, token: String): Request.Builder {
        return Request.Builder().url(url).header("Authorization", "Bearer $token")
    }
}

class OpenIslandDiscovery(context: Context) {
    private val appContext = context.applicationContext
    private val nsd = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val wifi = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private var lock: WifiManager.MulticastLock? = null
    private var listener: NsdManager.DiscoveryListener? = null

    fun start(onFound: (OpenIslandService) -> Unit, onError: (String) -> Unit) {
        stop()
        lock = wifi.createMulticastLock("open-island-mdns").also {
            it.setReferenceCounted(false)
            it.acquire()
        }
        val discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                onError("Discovery failed: $errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            override fun onServiceLost(serviceInfo: NsdServiceInfo) = Unit
            override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                if (serviceInfo.serviceType != "_openisland._tcp.") return
                nsd.resolveService(serviceInfo, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) = Unit
                    override fun onServiceResolved(resolved: NsdServiceInfo) {
                        val host = resolved.hostAddress() ?: return
                        onFound(OpenIslandService(resolved.serviceName, host, resolved.port))
                    }
                })
            }
        }
        listener = discoveryListener
        nsd.discoverServices("_openisland._tcp.", NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stop() {
        listener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        listener = null
        lock?.let { if (it.isHeld) it.release() }
        lock = null
    }
}

private fun NsdServiceInfo.hostAddress(): String? {
    val hostValue: InetAddress = host ?: return null
    return hostValue.hostAddress
}

private fun JSONArray.toSessions(): List<MobileSession> {
    return (0 until length()).map { getJSONObject(it).toSession() }
}

private fun JSONObject.toDetail(): MobileDetail {
    val session = getJSONObject("session").toSession()
    val context = getJSONArray("context")
    val items = (0 until context.length()).map { context.getJSONObject(it).toContextItem() }
    return MobileDetail(session, items)
}

private fun JSONObject.toSession(): MobileSession {
    return MobileSession(
        id = getString("id"),
        title = optString("title"),
        tool = optString("tool"),
        phase = optString("phase"),
        status = optString("status"),
        workspace = optNullableString("workspace"),
        workingDirectory = optNullableString("workingDirectory"),
        summary = optString("summary"),
        updatedAt = optString("updatedAt"),
        canReply = optBoolean("canReply"),
        unreadCompletion = optBoolean("unreadCompletion"),
    )
}

private fun JSONObject.toContextItem(): MobileContextItem {
    return MobileContextItem(
        role = optString("role"),
        text = optString("text"),
        timestamp = optNullableString("timestamp"),
    )
}

private fun JSONObject.optNullableString(name: String): String? {
    return if (has(name) && !isNull(name)) optString(name) else null
}

private fun String.urlPath(): String {
    return java.net.URLEncoder.encode(this, "UTF-8").replace("+", "%20")
}
