#lang racket/base

(provide (all-defined-out))

(define-logger token-bucket)

(struct waitq (heads tails))

(define (make-waitq) (waitq null null))
(define (waitq-size q) (+ (length (waitq-heads q)) (length (waitq-tails q))))
(define (waitq-empty? q)
  (and (null? (waitq-heads q))
       (null? (waitq-tails q))))
(define (waitq-enqueue q v)
  (struct-copy waitq q [tails (cons v (waitq-tails q))]))

(define (waitq-dequeue q)
  (define q1 (waitq-adjust q))
  (define hds (waitq-heads q1))
  (values (car hds)
          (struct-copy waitq q1 [heads (cdr hds)])))

(define (waitq-adjust q)
  (cond
    [(null? (waitq-heads q)) (waitq (reverse (waitq-tails q)) null)]
    [else q]))

(define (waitq-head q)
  (car (waitq-heads (waitq-adjust q))))

(define (waitq-tokens q)
  (car (waitq-head q)))

(define (token-bucket-process init-tokens max-tokens token-evt req-ch)
  (define (init)
    (log-token-bucket-info "token bucket starting ~a ~a" init-tokens max-tokens)
    (with-handlers ([exn:fail? (lambda (e)
                                 (log-token-bucket-error "unhandled exception: ~a" e))])
      (run init-tokens (make-waitq))))
  (define (run num-tokens waiters)
    (log-token-bucket-debug "tokens: ~a; needed: ~a; max: ~a; waiters: ~a"
                            num-tokens
                            (if (waitq-empty? waiters) 0 (waitq-tokens waiters))
                            max-tokens
                            (waitq-size waiters))
    (sync
     (handle-evt
      token-evt
      (lambda (amt)
        (log-token-bucket-debug "received ~a tokens" amt)
        (service (+ amt num-tokens) waiters)))
     (handle-evt
      req-ch
      (lambda (req)
        (log-token-bucket-debug "received request for ~a tokens" (car req))
        (service num-tokens (waitq-enqueue waiters req))))))
  (define (service num-tokens waiters)
    (cond
      [(or (waitq-empty? waiters)
           (> (waitq-tokens waiters) num-tokens))
       (run (min num-tokens max-tokens) waiters)]
      [else
       (define-values (w new-waiters) (waitq-dequeue waiters))
       (define tokens-left (- num-tokens (car w)))
       (log-token-bucket-debug "signalling waiter")
       (channel-put (cdr w) #t)
       (service tokens-left new-waiters)]))
  init)

(define (request-tokens timeout req-ch num-tokens)
  (define rpy-ch (make-channel))
  (channel-put req-ch (cons num-tokens rpy-ch))
  (sync/timeout timeout rpy-ch))

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
           (proc req-ch)))
       (lambda ()
         (custodian-shutdown-all cust)))))

  (test-with-token-bucket-process
   never-evt 0 100
   (lambda (req-ch)
     (check-false (request-tokens 0 req-ch 10))))

  (test-with-token-bucket-process
   never-evt 100 100
   (lambda (req-ch)
     (check-true (request-tokens 0 req-ch 10))))

  (test-with-token-bucket-process
    never-evt 100 100
    (lambda (req-ch)
      (define t1 (thread (lambda () (request-tokens #f req-ch 50))))
      (define t2 (thread (lambda () (request-tokens #f req-ch 50))))
      (check-true (thread-dead? t1))
      (check-true (thread-dead? t2))))
  )


