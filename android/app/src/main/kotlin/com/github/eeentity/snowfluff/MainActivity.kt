package com.github.eeentity.snowfluff

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
	companion object {
		private const val BACK_CHANNEL = "snowfluff/back"
	}

	private fun fallbackToSuperBack() {
		super.onBackPressed()
	}

	override fun onBackPressed() {
		val engine = flutterEngine
		if (engine != null) {
			MethodChannel(engine.dartExecutor.binaryMessenger, BACK_CHANNEL).invokeMethod(
				"onBackPressed",
				null,
				object : MethodChannel.Result {
					override fun success(result: Any?) {
						val consumed = result as? Boolean ?: false
						if (!consumed) {
							fallbackToSuperBack()
						}
					}

					override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
						fallbackToSuperBack()
					}

					override fun notImplemented() {
						fallbackToSuperBack()
					}
				}
			)
			return
		}
		fallbackToSuperBack()
	}
}
