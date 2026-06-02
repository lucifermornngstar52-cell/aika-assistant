/// Заглушка overlay entry point.
/// Нативный overlay теперь реализован в AikaOverlayService.kt (Android ImageView).
/// overlayMain сохранён для совместимости — не вызывается.
@pragma('vm:entry-point')
void overlayMain() {
  // Нативный overlay — см. AikaOverlayService.kt
}
