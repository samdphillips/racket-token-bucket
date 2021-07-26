#lang racket/base

(provide token-bucket?
         make-token-bucket
         token-bucket-take!)

(require token-bucket/private/tb-process)

(struct token-bucket (th req-ch))

(define (make-default-token-evt fill-rate)
  (define previous-time (current-milliseconds))
  (guard-evt
    (lambda ()
      (handle-evt
        (alarm-evt (+ 1000 (current-inexact-milliseconds)))
        (lambda (ignore)
          (define current (current-milliseconds))
          (define tokens (* (- current previous-time) fill-rate))
          (set! previous-time current)
          tokens)))))

(define (make-token-bucket fill-rate init-tokens max-tokens)
  (define token-evt (make-default-token-evt fill-rate))
  (define req-ch (make-channel))
  (define process-thread
    (thread (token-bucket-process init-tokens max-tokens token-evt req-ch)))
  (token-bucket process-thread req-ch))

(define (token-bucket-take! tb amount)
  (request-tokens 'token-bucket-take!
                  #f
                  (token-bucket-th tb)
                  (token-bucket-req-ch tb)
                  amount))

