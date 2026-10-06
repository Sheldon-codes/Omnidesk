package com.bigbrainzsolutions.omnidesk

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ManagedOutboundBackendMappingTest {
    @Test fun decodesDistinctBackendAndProviderIds() {
        val outbound = ManagedCallBackendClient.decodeOutbound(JSONObject()
            .put("success", true).put("call_id", "backend_123")
            .put("call_sid", "provider_456").put("normalized_to_number", "+254712345678"),
            "0712345678")
        assertEquals("backend_123", outbound.callId)
        assertEquals("provider_456", outbound.callSid)
        assertEquals("+254712345678", outbound.number)
    }

    @Test fun preservesDialedNumberWhenBackendDoesNotNormalize() {
        assertEquals("0712345678", ManagedCallBackendClient.decodeOutbound(JSONObject()
            .put("call_id", "abc").put("call_sid", "def"), "0712345678").number)
    }

    @Test fun rejectsFailedOrUncorrelatableInitiation() {
        assertThrows(IllegalStateException::class.java) {
            ManagedCallBackendClient.decodeOutbound(JSONObject().put("success", false), "0712345678")
        }
        assertThrows(IllegalArgumentException::class.java) {
            ManagedCallBackendClient.decodeOutbound(JSONObject().put("call_sid", "sid"), "0712345678")
        }
    }
}
