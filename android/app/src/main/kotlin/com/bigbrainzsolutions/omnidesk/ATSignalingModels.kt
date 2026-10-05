package com.bigbrainzsolutions.omnidesk

import org.json.JSONObject

/** Wire-level AT/Janus models. Sensitive values are never included in toString(). */
internal object ATSignalingModels {
    fun createCommand(): String = JSONObject().put("command", "create").toString()
    fun registerCommand(): String = JSONObject()
        .put("command", "message")
        .put("body", JSONObject().put("request", "register"))
        .toString()
    fun keepaliveCommand(): String = JSONObject().put("command", "keepalive").toString()
    fun destroyCommand(): String = JSONObject().put("command", "destroy").toString()
    fun callCommand(number: String, jsep: Map<String, Any?>): String = messageCommand(
        JSONObject().put("request", "call").put("to", number), jsep,
    )
    fun acceptCommand(jsep: Map<String, Any?>): String = messageCommand(
        JSONObject().put("request", "accept"), jsep,
    )
    fun controlCommand(request: String, fields: Map<String, Any?> = emptyMap()): String {
        val body = JSONObject().put("request", request)
        fields.forEach { (key, value) -> body.put(key, value) }
        return JSONObject().put("command", "message").put("body", body).toString()
    }
    fun trickleCommand(candidate: Map<String, Any?>?): String = JSONObject()
        .put("command", "trickle")
        .put("candidate", candidate?.let(::mapToJson) ?: JSONObject().put("completed", true))
        .toString()

    private fun mapToJson(fields: Map<String, Any?>): JSONObject = JSONObject().apply {
        fields.forEach { (key, value) -> put(key, value) }
    }

    private fun messageCommand(body: JSONObject, jsep: Map<String, Any?>): String = JSONObject()
        .put("command", "message")
        .put("body", body)
        // JSONObject(map) recursively serializes nested maps without changing SDP text.
        .put("jsep", JSONObject(jsep))
        .toString()

    sealed interface Incoming {
        data object CreateSucceeded : Incoming
        data object Registered : Incoming
        data class RegistrationFailed(val code: String?) : Incoming
        data class Known(val name: String) : Incoming
        data class Trickle(val candidate: Map<String, Any?>?) : Incoming
        data class Event(
            val name: String,
            val payload: Map<String, Any?>,
            val jsep: Map<String, Any?>?,
        ) : Incoming
        data object Unknown : Incoming
    }

    fun decode(text: String): Incoming = try {
        val root = JSONObject(text)
        when (root.optString("response")) {
            "success" -> Incoming.CreateSucceeded
            "closed" -> Incoming.Known("closed")
            "offline" -> Incoming.Known("offline")
            "hangup" -> Incoming.Known("hangup")
            "ack" -> Incoming.Known("ack")
            "webrtcup" -> Incoming.Known("webrtcup")
            "trickle" -> Incoming.Trickle(root.optJSONObject("candidate")?.toMap())
            "event" -> {
                val result = root.optJSONObject("eventdata")?.optJSONObject("result")
                val event = result?.optString("event").orEmpty()
                when (event) {
                    "registered" -> Incoming.Registered
                    "registration_failed" -> Incoming.RegistrationFailed(
                        result?.opt("code")?.toString()?.take(80),
                    )
                    "" -> Incoming.Unknown
                    else -> Incoming.Event(
                        event,
                        result?.toMap().orEmpty(),
                        root.optJSONObject("jsep")?.toMap(),
                    )
                }
            }
            else -> Incoming.Unknown
        }
    } catch (_: Exception) {
        Incoming.Unknown
    }

    private fun JSONObject.toMap(): Map<String, Any?> = keys().asSequence().associateWith { key ->
        when (val value = opt(key)) {
            JSONObject.NULL -> null
            is JSONObject -> value.toMap()
            is org.json.JSONArray -> (0 until value.length()).map { index ->
                when (val item = value.opt(index)) {
                    JSONObject.NULL -> null
                    is JSONObject -> item.toMap()
                    else -> item
                }
            }
            else -> value
        }
    }
}
