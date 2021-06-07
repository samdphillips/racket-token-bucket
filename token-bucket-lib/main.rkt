#lang racket/base

(define (waiter-tokens waiters) (caar waiters))
(define (waiter-channel waiters) (cdar waiters))

(define (token-bucket-process init-tokens max-tokens token-evt req-evt)
  (define (init)
    (run init-tokens null))
  (define (run num-tokens waiters)
    (sync
     (handle-evt
      token-evt
      (lambda (amt)
        (service (+ amt num-tokens) waiters)))
     (handle-evt
      req-evt
      (lambda (toks rpy-ch)
        (service num-tokens (cons (cons toks rpy-ch) waiters))))))
  (define (service num-tokens waiters)
    (cond
      [(null? waiters)
       (run (min num-tokens max-tokens) null)]

      [(> (waiter-tokens waiters) num-tokens)
       (run (min num-tokens max-tokens) waiters)]

      [else
       (channel-put (waiter-channel waiters) #t)
       (run (- num-tokens (waiter-tokens waiters))
            (cdr waiters))]))
  init)

