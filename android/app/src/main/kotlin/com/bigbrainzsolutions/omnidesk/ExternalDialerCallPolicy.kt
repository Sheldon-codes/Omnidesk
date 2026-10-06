package com.bigbrainzsolutions.omnidesk

import android.content.Context
import android.net.Uri
import android.telephony.PhoneNumberUtils

/** Validation only; the backend remains the authority for national-number normalization. */
internal object ExternalDialerCallPolicy {
    fun destination(context: Context, address: Uri?, managedAccount: Boolean,
                    managedSelected: Boolean, accountEnabled: Boolean?): String? =
        destination(address?.scheme, address?.schemeSpecificPart, managedAccount, managedSelected, accountEnabled) { number ->
            PhoneNumberUtils.isEmergencyNumber(number) || PhoneNumberUtils.isLocalEmergencyNumber(context, number)
        }

    internal fun destination(scheme: String?, dialed: String?, managedAccount: Boolean, managedSelected: Boolean,
                             accountEnabled: Boolean?, isEmergency: (String) -> Boolean): String? {
        if (!managedAccount || !managedSelected || accountEnabled == false || scheme != "tel") return null
        val raw = dialed?.trim() ?: return null
        if (raw.length !in 5..40 || !raw.matches(Regex("\\+?[0-9 ()-]+"))) return null
        val number = raw.filter { it.isDigit() || it == '+' }
        val digits = number.removePrefix("+")
        if (digits.length !in 5..20 || !digits.all(Char::isDigit) || isEmergency(number) || isEmergency(digits)) return null
        return number
    }
}
