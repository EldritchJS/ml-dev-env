import os, time
import torch
import torch.distributed as dist

def parse_bytes(s: str) -> int:
    s = s.strip().lower()
    mult = 1
    if s.endswith("k"): mult = 1024; s = s[:-1]
    elif s.endswith("m"): mult = 1024**2; s = s[:-1]
    elif s.endswith("g"): mult = 1024**3; s = s[:-1]
    return int(float(s) * mult)

def main():
    dist.init_process_group(backend="nccl")
    rank = dist.get_rank()
    world = dist.get_world_size()
    local_rank = int(os.environ.get("LOCAL_RANK", "0"))
    torch.cuda.set_device(local_rank)

    # knobs (override via env)
    msg = parse_bytes(os.environ.get("NCCL_BENCH_BYTES", "256m"))
    iters = int(os.environ.get("NCCL_BENCH_ITERS", "50"))
    warmup = int(os.environ.get("NCCL_BENCH_WARMUP", "10"))
    op = os.environ.get("NCCL_BENCH_OP", "all_reduce").lower()

    # float32 like nccl-tests default-ish for perf sanity
    n = msg // 4
    x = torch.ones(n, device="cuda", dtype=torch.float32)

    # warmup
    for _ in range(warmup):
        if op == "all_reduce":
            dist.all_reduce(x)
        elif op == "all_gather":
            out = [torch.empty_like(x) for _ in range(world)]
            dist.all_gather(out, x)
        elif op == "broadcast":
            dist.broadcast(x, src=0)
        dist.barrier()

    torch.cuda.synchronize()
    dist.barrier()

    t0 = time.time()
    for _ in range(iters):
        if op == "all_reduce":
            dist.all_reduce(x)
        elif op == "all_gather":
            out = [torch.empty_like(x) for _ in range(world)]
            dist.all_gather(out, x)
        elif op == "broadcast":
            dist.broadcast(x, src=0)
        dist.barrier()
    torch.cuda.synchronize()
    dist.barrier()
    t1 = time.time()

    sec = (t1 - t0) / iters
    gib = msg / (1024**3)

    # very rough "algorithmic" BW:
    # all_reduce moves ~2*(world-1)/world * msg per rank for ring (order-of-magnitude)
    if op == "all_reduce":
        alg = 2.0 * (world - 1) / world * gib
    elif op == "all_gather":
        alg = (world - 1) * gib
    else:  # broadcast
        alg = gib

    bw = alg / sec
    if rank == 0:
        print(f"[bench] op={op} world={world} bytes={msg} iters={iters} avg_sec={sec:.6f} approx_alg_BW={bw:.2f} GiB/s", flush=True)

    dist.destroy_process_group()

if __name__ == "__main__":
    main()
