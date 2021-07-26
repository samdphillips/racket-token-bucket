#lang racket/base

(require token-bucket/private/queue)
(provide token-bucket-process
         request-tokens)

(define-logger token-bucket)

(define (token-bucket-process init-tokens max-tokens token-evt req-ch)
  (define (init)
    (log-token-bucket-info "token bucket starting ~a ~a" init-tokens max-tokens)
    (with-handlers ([exn:fail? (lambda (e)
                                 (log-token-bucket-error "unhandled exception: ~a" e))])
      (run init-tokens (make-waitq))))

  (define (token-bucket-full? num-tokens) (>= num-tokens max-tokens))

  (define (run num-tokens waiters)
    (log-token-bucket-debug "tokens: ~a; needed: ~a; max: ~a; waiters: ~a"
                            num-tokens
                            (if (waitq-empty? waiters) 0 (waitq-tokens waiters))
                            max-tokens
                            (waitq-size waiters))
    (sync
     (cond
       [(token-bucket-full? num-tokens) never-evt]
       [else
        (handle-evt
         token-evt
         (lambda (amt)
           (log-token-bucket-debug "received ~a tokens" amt)
           (service (+ amt num-tokens) waiters)))])
     (handle-evt
      req-ch
      (lambda (req)
        (log-token-bucket-info "received request for ~a tokens" (waiter-tokens req))
        (service num-tokens (waitq-enqueue waiters req))))))

  (define (service num-tokens waiters)
    (cond
      [(or (waitq-empty? waiters) (> (waitq-tokens waiters) num-tokens))
       (run (min num-tokens max-tokens) waiters)]
      [else
       (define-values (w new-waiters) (waitq-dequeue waiters))
       (define tokens-left (- num-tokens (waiter-tokens w)))
       (thread
        (lambda ()
          (log-token-bucket-info "enough tokens [~a] to signal waiter" (waiter-tokens w))
          (log-token-bucket-info "~a tokens left" tokens-left)
          (channel-put (waiter-channel w) #t)))
       (service tokens-left new-waiters)]))
  init)

(define (request-tokens who timeout th req-ch num-tokens)
  (define rpy-ch (make-channel))
  (define dead-evt
    (handle-evt
      (thread-dead-evt th)
      (lambda (ignore)
        (error who "token-bucket thread is dead"))))
  (channel-put req-ch (make-waiter num-tokens rpy-ch))
  (sync/timeout timeout dead-evt rpy-ch))

(module+ test
  (require rackunit)

  (define (test-with-token-bucket-process token-evt num-tokens max-tokens proc)
    (let ()
      (define cust (make-custodian))
      (dynamic-wind
       void
       (lambda ()
         (parameterize ([current-custodian cust])
           (define req-ch (make-channel))
           (define th (thread (token-bucket-process num-tokens max-tokens token-evt req-ch)))
           (proc th req-ch)))
       (lambda ()
         (custodian-shutdown-all cust)))))

  (test-case "check no filling with no tokens"
    (test-with-token-bucket-process
     never-evt 0 100
     (lambda (th req-ch)
       (check-false (request-tokens 'request-tokens 0 th req-ch 10)))))

  (test-case "check no filling with full tokens"
    (test-with-token-bucket-process
     never-evt 100 100
     (lambda (th req-ch)
       (check-true (request-tokens 'request-tokens 0 th req-ch 10)))))

  (test-case "check no filling with taking all tokens in two requests"
    (test-with-token-bucket-process
     never-evt 100 100
     (lambda (th req-ch)
       (define v1 (request-tokens 'request-tokens 5 th req-ch 50))
       (define v2 (request-tokens 'request-tokens 5 th req-ch 50))
       (check-true v1)
       (check-true v2))))

  (test-case "check fill enough for request"
    (define fill-ch (make-channel))
    (test-with-token-bucket-process
     fill-ch 0 100
     (lambda (th req-ch)
       (define v 42)
       (define t
         (thread (lambda () (set! v (request-tokens 'request-tokens 5 th req-ch 50)))))
       (channel-put fill-ch 50)
       (thread-wait t)
       (check-true v)))))


