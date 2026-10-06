package com.bigbrainzsolutions.omnidesk

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class ManagedCallAccountPolicyTest {
    @Test fun disabledMigrationKeepsExistingSelfManagedAccount() {
        assertEquals(
            ManagedCallAccountPolicy.Account.SELF_MANAGED,
            ManagedCallAccountPolicy.select(managedRequested = false, managedAccountEnabled = false),
        )
    }

    @Test fun explicitlyEnabledAndAvailableUsesSystemManagedAccount() {
        assertEquals(
            ManagedCallAccountPolicy.Account.SYSTEM_MANAGED,
            ManagedCallAccountPolicy.select(managedRequested = true, managedAccountEnabled = true),
        )
    }

    @Test fun unknownAccountStatusDoesNotRequestSensitivePhonePermissions() {
        assertEquals(
            ManagedCallAccountPolicy.Account.SYSTEM_MANAGED,
            ManagedCallAccountPolicy.select(managedRequested = true, managedAccountEnabled = null),
        )
    }

    @Test fun selectedButDisabledFailsInsteadOfFallingBackMidCall() {
        val error = assertThrows(IllegalStateException::class.java) {
            ManagedCallAccountPolicy.select(managedRequested = true, managedAccountEnabled = false)
        }
        assertEquals("system_managed_calling_not_enabled_in_android_settings", error.message)
    }
}
