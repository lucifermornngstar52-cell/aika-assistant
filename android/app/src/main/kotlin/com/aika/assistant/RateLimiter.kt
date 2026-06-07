package com.aika.assistant

import java.util.concurrent.ConcurrentHashMap

/**
 * Per-source token-bucket rate limiter.
 * Адаптирован из openclaw-assistant (MIT License).
 *
 * Capacity: 20 запросов. Refill: 1 токен / 300 ms (~3 req/s sustained).
 * Предотвращает crash-loop в SmartActionLoop и бесконечные речевые циклы.
 */
class RateLimiter(
    private val capacity: Int = 20,
    private val refillIntervalMs: Long = 300L,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private data class Bucket(var tokens: Double, var lastRefillMs: Long)
    private val buckets = ConcurrentHashMap<String, Bucket>()

    fun tryAcquire(key: String = "default"): Boolean {
        val nowMs = now()
        val bucket = buckets.compute(key) { _, existing ->
            val b = existing ?: Bucket(capacity.toDouble(), nowMs)
            val elapsed = nowMs - b.lastRefillMs
            if (elapsed > 0) {
                b.tokens = (b.tokens + elapsed.toDouble() / refillIntervalMs)
                    .coerceAtMost(capacity.toDouble())
                b.lastRefillMs = nowMs
            }
            b
        }!!
        return if (bucket.tokens >= 1.0) { bucket.tokens -= 1.0; true } else false
    }

    fun reset(key: String = "default") {
        buckets.remove(key)
    }
}
