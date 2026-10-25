# Flutter and the plugins used here ship their own consumer rules. Add app-specific keep rules below if a
# release build crashes with ClassNotFoundException after minification.

# The text recognition plugin refers to script models this app does not ship (Chinese, Japanese, Korean).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
