package com.bigbrainzsolutions.omnidesk

/** Selects the Telecom account once, before create/place; it never retries across account types. */
internal object ManagedCallAccountPolicy {
    enum class Account { SELF_MANAGED, SYSTEM_MANAGED }

    fun select(managedRequested: Boolean, managedAccountEnabled: Boolean?): Account = when {
        !managedRequested -> Account.SELF_MANAGED
        managedAccountEnabled != false -> Account.SYSTEM_MANAGED
        else -> throw IllegalStateException("system_managed_calling_not_enabled_in_android_settings")
    }
}
