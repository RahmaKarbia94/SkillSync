package worker

import (
	"context"
	"fmt"
	"log"
	"sync"
	"time"
)

type Task interface {
	Execute(ctx context.Context)
}

type Pool struct {
	tasks   chan Task
	workers int
	wg      sync.WaitGroup
	ctx     context.Context
	cancel  context.CancelFunc
	mu      sync.Mutex
	started bool
}

func NewPool(workers, queueSize int) *Pool {
	ctx, cancel := context.WithCancel(context.Background())
	return &Pool{
		tasks:   make(chan Task, queueSize),
		workers: workers,
		ctx:     ctx,
		cancel:  cancel,
	}
}

func (p *Pool) Start() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.started {
		return
	}
	p.started = true

	for i := 0; i < p.workers; i++ {
		p.wg.Add(1)
		go p.worker(i)
	}

	log.Printf("worker pool started with %d workers", p.workers)
}

func (p *Pool) worker(id int) {
	defer p.wg.Done()
	for {
		select {
		case task := <-p.tasks:
			p.runTask(id, task)
		case <-p.ctx.Done():
			p.drainRemaining(id)
			return
		}
	}
}

func (p *Pool) drainRemaining(id int) {
	for {
		select {
		case task := <-p.tasks:
			p.runTask(id, task)
		default:
			return
		}
	}
}

func (p *Pool) runTask(workerID int, task Task) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("worker %d: recovered from panic: %v", workerID, r)
		}
	}()
	task.Execute(p.ctx)
}

func (p *Pool) Submit(task Task) error {
	select {
	case p.tasks <- task:
		return nil
	case <-p.ctx.Done():
		return fmt.Errorf("worker pool is shutting down")
	}
}

func (p *Pool) Shutdown(timeout time.Duration) error {
	p.cancel()

	done := make(chan struct{})
	go func() {
		p.wg.Wait()
		close(done)
	}()

	select {
	case <-done:
		log.Println("worker pool shut down cleanly")
		return nil
	case <-time.After(timeout):
		return fmt.Errorf("worker pool shutdown timed out after %s", timeout)
	}
}