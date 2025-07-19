;; Cross-Examination Contract
;; Manages remote witness questioning procedures

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-SESSION-NOT-FOUND (err u301))
(define-constant ERR-INVALID-PARTICIPANT (err u302))
(define-constant ERR-SESSION-CLOSED (err u303))
(define-constant ERR-QUESTION-LIMIT (err u304))

;; Data Variables
(define-data-var next-session-id uint u1)
(define-data-var next-question-id uint u1)
(define-data-var max-questions-per-session uint u50)

;; Data Maps
(define-map examination-sessions
  { session-id: uint }
  {
    testimony-id: uint,
    examiner: principal,
    witness: principal,
    scheduled-at: uint,
    started-at: (optional uint),
    ended-at: (optional uint),
    status: (string-ascii 20),
    question-count: uint,
    session-type: (string-ascii 30)
  }
)

(define-map questions
  { question-id: uint }
  {
    session-id: uint,
    questioner: principal,
    question-text: (string-ascii 500),
    asked-at: uint,
    question-type: (string-ascii 20),
    objection-raised: bool
  }
)

(define-map answers
  { question-id: uint }
  {
    respondent: principal,
    answer-text: (string-ascii 1000),
    answered-at: uint,
    answer-duration: uint,
    confidence-level: uint
  }
)

(define-map session-participants
  { session-id: uint, participant: principal }
  {
    role: (string-ascii 20),
    joined-at: uint,
    active: bool
  }
)

;; Public Functions

;; Schedule examination session
(define-public (schedule-examination
  (testimony-id uint)
  (examiner principal)
  (witness principal)
  (scheduled-at uint)
  (session-type (string-ascii 30)))
  (let
    (
      (session-id (var-get next-session-id))
    )
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender examiner)) ERR-NOT-AUTHORIZED)

    (map-set examination-sessions
      { session-id: session-id }
      {
        testimony-id: testimony-id,
        examiner: examiner,
        witness: witness,
        scheduled-at: scheduled-at,
        started-at: none,
        ended-at: none,
        status: "scheduled",
        question-count: u0,
        session-type: session-type
      }
    )

    (map-set session-participants
      { session-id: session-id, participant: examiner }
      {
        role: "examiner",
        joined-at: scheduled-at,
        active: true
      }
    )

    (map-set session-participants
      { session-id: session-id, participant: witness }
      {
        role: "witness",
        joined-at: scheduled-at,
        active: true
      }
    )

    (var-set next-session-id (+ session-id u1))
    (ok session-id)
  )
)

;; Start examination session
(define-public (start-session (session-id uint))
  (let
    (
      (session-data (unwrap! (map-get? examination-sessions { session-id: session-id }) ERR-SESSION-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (or (is-eq tx-sender (get examiner session-data)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status session-data) "scheduled") ERR-SESSION-CLOSED)

    (map-set examination-sessions
      { session-id: session-id }
      (merge session-data {
        started-at: (some current-time),
        status: "active"
      })
    )
    (ok true)
  )
)

;; Ask question during examination
(define-public (ask-question
  (session-id uint)
  (question-text (string-ascii 500))
  (question-type (string-ascii 20)))
  (let
    (
      (session-data (unwrap! (map-get? examination-sessions { session-id: session-id }) ERR-SESSION-NOT-FOUND))
      (question-id (var-get next-question-id))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (current-count (get question-count session-data))
    )
    (asserts! (is-eq tx-sender (get examiner session-data)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status session-data) "active") ERR-SESSION-CLOSED)
    (asserts! (< current-count (var-get max-questions-per-session)) ERR-QUESTION-LIMIT)

    (map-set questions
      { question-id: question-id }
      {
        session-id: session-id,
        questioner: tx-sender,
        question-text: question-text,
        asked-at: current-time,
        question-type: question-type,
        objection-raised: false
      }
    )

    (map-set examination-sessions
      { session-id: session-id }
      (merge session-data {
        question-count: (+ current-count u1)
      })
    )

    (var-set next-question-id (+ question-id u1))
    (ok question-id)
  )
)

;; Answer question
(define-public (answer-question
  (question-id uint)
  (answer-text (string-ascii 1000))
  (answer-duration uint)
  (confidence-level uint))
  (let
    (
      (question-data (unwrap! (map-get? questions { question-id: question-id }) ERR-SESSION-NOT-FOUND))
      (session-data (unwrap! (map-get? examination-sessions { session-id: (get session-id question-data) }) ERR-SESSION-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (is-eq tx-sender (get witness session-data)) ERR-NOT-AUTHORIZED)
    (asserts! (< confidence-level u101) ERR-INVALID-PARTICIPANT)

    (map-set answers
      { question-id: question-id }
      {
        respondent: tx-sender,
        answer-text: answer-text,
        answered-at: current-time,
        answer-duration: answer-duration,
        confidence-level: confidence-level
      }
    )
    (ok true)
  )
)

;; End examination session
(define-public (end-session (session-id uint))
  (let
    (
      (session-data (unwrap! (map-get? examination-sessions { session-id: session-id }) ERR-SESSION-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (or (is-eq tx-sender (get examiner session-data)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status session-data) "active") ERR-SESSION-CLOSED)

    (map-set examination-sessions
      { session-id: session-id }
      (merge session-data {
        ended-at: (some current-time),
        status: "completed"
      })
    )
    (ok true)
  )
)

;; Read-only Functions

;; Get examination session
(define-read-only (get-session (session-id uint))
  (map-get? examination-sessions { session-id: session-id })
)

;; Get question details
(define-read-only (get-question (question-id uint))
  (map-get? questions { question-id: question-id })
)

;; Get answer details
(define-read-only (get-answer (question-id uint))
  (map-get? answers { question-id: question-id })
)

;; Get session participant info
(define-read-only (get-participant (session-id uint) (participant principal))
  (map-get? session-participants { session-id: session-id, participant: participant })
)

;; Get total sessions count
(define-read-only (get-total-sessions)
  (- (var-get next-session-id) u1)
)
