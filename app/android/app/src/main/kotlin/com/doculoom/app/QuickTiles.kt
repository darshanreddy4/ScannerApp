package com.doculoom.app

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** A quick-settings tile that opens one screen of the app. */
abstract class QuickTile(private val actionId: String) : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(QuickActions.pendingIntent(this, actionId))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(QuickActions.intent(this, actionId))
        }
    }
}

class ScanTile : QuickTile(QuickActions.SCAN)

class IdPhotoTile : QuickTile(QuickActions.ID_PHOTO)

class ReadPdfTile : QuickTile(QuickActions.READ_PDF)
