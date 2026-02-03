#!/usr/bin/env python3
"""
Test multi-GPU setup and NCCL communication
"""
import torch
import torch.distributed as dist
from datetime import datetime

def test_gpu_availability():
    """Test basic GPU availability"""
    print("=" * 60)
    print("GPU Availability Test")
    print("=" * 60)

    cuda_available = torch.cuda.is_available()
    print(f"CUDA Available: {cuda_available}")

    if cuda_available:
        num_gpus = torch.cuda.device_count()
        print(f"Number of GPUs: {num_gpus}")

        for i in range(num_gpus):
            props = torch.cuda.get_device_properties(i)
            print(f"\nGPU {i}: {props.name}")
            print(f"  Compute Capability: {props.major}.{props.minor}")
            print(f"  Total Memory: {props.total_memory / 1024**3:.2f} GB")
            print(f"  Multi-Processor Count: {props.multi_processor_count}")
    print()

def test_nccl():
    """Test NCCL backend availability"""
    print("=" * 60)
    print("NCCL Backend Test")
    print("=" * 60)

    nccl_available = dist.is_nccl_available()
    print(f"NCCL Available: {nccl_available}")

    if torch.cuda.is_available():
        # Test peer-to-peer access
        num_gpus = torch.cuda.device_count()
        print(f"\nPeer-to-Peer Access Matrix:")
        for i in range(num_gpus):
            for j in range(num_gpus):
                if i != j:
                    can_access = torch.cuda.can_device_access_peer(i, j)
                    print(f"  GPU {i} -> GPU {j}: {'Yes' if can_access else 'No'}")
    print()

def test_data_transfer():
    """Test GPU-to-GPU data transfer"""
    print("=" * 60)
    print("GPU Data Transfer Test")
    print("=" * 60)

    if not torch.cuda.is_available():
        print("No CUDA devices available")
        return

    num_gpus = torch.cuda.device_count()
    size = (1000, 1000)

    for gpu_id in range(num_gpus):
        # Create tensor on GPU
        device = f'cuda:{gpu_id}'
        start = datetime.now()
        tensor = torch.randn(size, device=device)
        torch.cuda.synchronize(gpu_id)
        elapsed = (datetime.now() - start).total_seconds() * 1000

        print(f"GPU {gpu_id}: Created {size} tensor in {elapsed:.2f} ms")

        # Test computation
        start = datetime.now()
        result = torch.mm(tensor, tensor)
        torch.cuda.synchronize(gpu_id)
        elapsed = (datetime.now() - start).total_seconds() * 1000

        print(f"GPU {gpu_id}: Matrix multiply in {elapsed:.2f} ms")
    print()

def test_multi_gpu_model():
    """Test simple multi-GPU model"""
    print("=" * 60)
    print("Multi-GPU Model Test")
    print("=" * 60)

    if not torch.cuda.is_available():
        print("No CUDA devices available")
        return

    num_gpus = torch.cuda.device_count()
    if num_gpus < 2:
        print(f"Need at least 2 GPUs, found {num_gpus}")
        return

    # Simple model
    model = torch.nn.Sequential(
        torch.nn.Linear(1024, 2048),
        torch.nn.ReLU(),
        torch.nn.Linear(2048, 1024)
    )

    # Wrap with DataParallel
    if num_gpus > 1:
        model = torch.nn.DataParallel(model)
        print(f"Model wrapped with DataParallel across {num_gpus} GPUs")

    model = model.cuda()

    # Test forward pass
    batch_size = 32
    x = torch.randn(batch_size, 1024).cuda()

    start = datetime.now()
    y = model(x)
    torch.cuda.synchronize()
    elapsed = (datetime.now() - start).total_seconds() * 1000

    print(f"Forward pass: {elapsed:.2f} ms")
    print(f"Output shape: {y.shape}")
    print()

if __name__ == "__main__":
    test_gpu_availability()
    test_nccl()
    test_data_transfer()
    test_multi_gpu_model()

    print("=" * 60)
    print("All tests completed!")
    print("=" * 60)
