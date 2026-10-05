package com.bigbrainzsolutions.omnidesk

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit

/** One-shot AT registration transport. Callbacks are generation-fenced by the coordinator. */
internal interface ATSignalingTransport {
    fun connect(gateway: String, capabilityToken: String)
    fun send(text: String): Boolean
    fun dispose()
}

internal class ATSignalingClient(
    private val listener: Listener,
    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS)
        .writeTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .build(),
) : ATSignalingTransport {
    interface Listener {
        fun onSocketOpened(selectedProtocol: String?)
        fun onText(text: String)
        fun onClosed()
        fun onFailure()
    }

    private var socket: WebSocket? = null
    private var disposed = false

    override fun connect(gateway: String, capabilityToken: String) {
        check(!disposed)
        val request = Request.Builder()
            .url(gateway)
            // Keep the exact iOS subprotocol offer order and values. Never log this Request.
            .header("Sec-WebSocket-Protocol", "at-protocol, $capabilityToken")
            .build()
        socket = client.newWebSocket(request, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                listener.onSocketOpened(response.header("Sec-WebSocket-Protocol"))
            }
            override fun onMessage(webSocket: WebSocket, text: String) = listener.onText(text)
            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) = listener.onClosed()
            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) = listener.onFailure()
        })
    }

    override fun send(text: String): Boolean = !disposed && socket?.send(text) == true

    override fun dispose() {
        if (disposed) return
        disposed = true
        socket?.close(1000, null)
        socket = null
        client.dispatcher.cancelAll()
        client.connectionPool.evictAll()
    }

    companion object {
        private const val CONNECT_TIMEOUT_SECONDS = 12L
    }
}
