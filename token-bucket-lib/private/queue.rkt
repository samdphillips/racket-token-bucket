#lang racket/base

(provide make-waitq
         waitq-dequeue
         waitq-empty?
         waitq-enqueue
         waitq-size
         waitq-tokens

         make-waiter
         waiter-tokens
         waiter-channel)

;; Purely functional FIFO

(define (make-waiter tokens ch) (cons tokens ch))
(define (waiter-tokens w) (car w))
(define (waiter-channel w) (cdr w))

(struct waitq (heads tails))

(define (make-waitq) (waitq null null))

(define (waitq-size q)
  (+ (length (waitq-heads q)) (length (waitq-tails q))))

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

