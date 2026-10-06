package com.bigbrainzsolutions.omnidesk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ExternalDialerCallPolicyTest {
    private val emergency: (String) -> Boolean = { it == "911" || it == "112" }

    @Test fun acceptsOrdinaryNationalAndInternationalNumbersWithoutBackendRewriting() {
        assertEquals("0712345678", destination("0712 345 678"))
        assertEquals("+254712345678", destination("+254 712 345 678"))
    }

    @Test fun rejectsWrongAccountOrDisabledMigration() {
        assertNull(ExternalDialerCallPolicy.destination("tel", "0712345678", false, true, true, emergency))
        assertNull(ExternalDialerCallPolicy.destination("tel", "0712345678", true, false, true, emergency))
        assertNull(ExternalDialerCallPolicy.destination("tel", "0712345678", true, true, false, emergency))
        assertEquals("0712345678", ExternalDialerCallPolicy.destination("tel", "0712345678", true, true, null, emergency))
    }

    @Test fun rejectsUnsupportedUrisAndServiceCodes() {
        assertNull(ExternalDialerCallPolicy.destination("sip", "0712345678", true, true, true, emergency))
        assertNull(destination("*123#"))
        assertNull(destination("0712345678,123"))
        assertNull(destination("0712345678;123"))
        assertNull(destination("112"))
        assertNull(destination("+"))
        assertNull(destination("123456789012345678901"))
    }

    private fun destination(value: String): String? =
        ExternalDialerCallPolicy.destination("tel", value, true, true, true, emergency)
}
