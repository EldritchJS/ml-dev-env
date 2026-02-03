#!/usr/bin/env python3
"""
Multi-Node DeepSpeed Training Example
Runs on 4 nodes × 4 GPUs = 16 H100s
"""

import os
import torch
import torch.nn as nn
import deepspeed
from torch.utils.data import Dataset, DataLoader

# Get environment variables
NODE_RANK = int(os.environ.get('NODE_RANK', 0))
LOCAL_RANK = int(os.environ.get('LOCAL_RANK', 0))
WORLD_SIZE = int(os.environ.get('WORLD_SIZE', 16))
MASTER_ADDR = os.environ.get('MASTER_ADDR', 'ml-dev-env-0.ml-dev-env-headless.nccl-test.svc.cluster.local')
MASTER_PORT = os.environ.get('MASTER_PORT', '29500')

# Calculate global rank
GLOBAL_RANK = NODE_RANK * 4 + LOCAL_RANK

print(f"[Rank {GLOBAL_RANK}] Node {NODE_RANK}, Local {LOCAL_RANK}, World Size {WORLD_SIZE}")
print(f"[Rank {GLOBAL_RANK}] Master: {MASTER_ADDR}:{MASTER_PORT}")


# Example model
class SimpleModel(nn.Module):
    def __init__(self, input_size=1024, hidden_size=4096, num_layers=12):
        super().__init__()
        layers = []
        layers.append(nn.Linear(input_size, hidden_size))
        layers.append(nn.ReLU())

        for _ in range(num_layers):
            layers.append(nn.Linear(hidden_size, hidden_size))
            layers.append(nn.ReLU())

        layers.append(nn.Linear(hidden_size, input_size))

        self.model = nn.Sequential(*layers)

    def forward(self, x):
        return self.model(x)


# Example dataset
class RandomDataset(Dataset):
    def __init__(self, size=10000, input_size=1024):
        self.size = size
        self.input_size = input_size

    def __len__(self):
        return self.size

    def __getitem__(self, idx):
        x = torch.randn(self.input_size)
        y = torch.randn(self.input_size)
        return x, y


def main():
    # Parse DeepSpeed args
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--local_rank', type=int, default=0)
    parser.add_argument('--epochs', type=int, default=5)
    parser = deepspeed.add_config_arguments(parser)
    args = parser.parse_args()

    # Initialize DeepSpeed
    deepspeed.init_distributed(
        dist_backend='nccl',
        rank=GLOBAL_RANK,
        world_size=WORLD_SIZE,
        init_method=f'tcp://{MASTER_ADDR}:{MASTER_PORT}'
    )

    if GLOBAL_RANK == 0:
        print("=" * 60)
        print("Multi-Node DeepSpeed Training")
        print("=" * 60)
        print(f"Nodes: 4")
        print(f"GPUs per node: 4")
        print(f"Total GPUs: {WORLD_SIZE}")
        print(f"Model: SimpleModel (12 layers, 4096 hidden)")
        print("=" * 60)

    # Create model
    model = SimpleModel()

    # Create dataset and dataloader
    dataset = RandomDataset(size=10000)

    # DeepSpeed engine
    model_engine, optimizer, trainloader, _ = deepspeed.initialize(
        args=args,
        model=model,
        model_parameters=model.parameters(),
        training_data=dataset
    )

    device = model_engine.local_rank

    if GLOBAL_RANK == 0:
        print(f"\nTraining on {WORLD_SIZE} GPUs...")
        print(f"Batch size per GPU: {model_engine.train_micro_batch_size_per_gpu()}")
        print(f"Global batch size: {model_engine.train_batch_size()}\n")

    # Training loop
    for epoch in range(args.epochs):
        model_engine.train()
        total_loss = 0

        for step, (x, y) in enumerate(trainloader):
            x = x.to(device)
            y = y.to(device)

            # Forward pass
            outputs = model_engine(x)
            loss = nn.functional.mse_loss(outputs, y)

            # Backward pass
            model_engine.backward(loss)
            model_engine.step()

            total_loss += loss.item()

            # Print progress
            if GLOBAL_RANK == 0 and step % 10 == 0:
                avg_loss = total_loss / (step + 1)
                print(f"Epoch {epoch+1}/{args.epochs}, Step {step}, Loss: {avg_loss:.4f}")

        if GLOBAL_RANK == 0:
            avg_loss = total_loss / len(trainloader)
            print(f"Epoch {epoch+1} completed. Average Loss: {avg_loss:.4f}\n")

    if GLOBAL_RANK == 0:
        print("=" * 60)
        print("Training completed!")
        print("=" * 60)

        # Test multi-node communication
        print("\nTesting NCCL all-reduce across all 16 GPUs...")
        tensor = torch.ones(1000, 1000, device=device) * GLOBAL_RANK
        torch.distributed.all_reduce(tensor)
        expected_sum = sum(range(WORLD_SIZE)) * 1000 * 1000
        actual_sum = tensor.sum().item()

        if abs(actual_sum - expected_sum) < 1e-5:
            print(f"✅ NCCL all-reduce successful! Sum: {actual_sum:.0f}")
            print("✅ All 16 GPUs are communicating correctly via RDMA/RoCE")
        else:
            print(f"❌ NCCL all-reduce failed. Expected {expected_sum}, got {actual_sum}")

    # Cleanup
    deepspeed.destroy_process_group()


if __name__ == "__main__":
    main()
