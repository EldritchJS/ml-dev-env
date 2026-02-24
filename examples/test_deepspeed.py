#!/usr/bin/env python3
"""
Test DeepSpeed distributed training with multi-GPU
Run with: deepspeed --num_gpus=4 test_deepspeed.py
"""
import argparse

import deepspeed
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset


class SimpleModel(nn.Module):
    """Simple neural network for testing"""

    def __init__(self, input_size=1024, hidden_size=2048, output_size=10):
        super().__init__()
        self.layers = nn.Sequential(
            nn.Linear(input_size, hidden_size),
            nn.ReLU(),
            nn.Linear(hidden_size, hidden_size),
            nn.ReLU(),
            nn.Linear(hidden_size, output_size),
        )

    def forward(self, x):
        return self.layers(x)


def create_dataset(num_samples=1000, input_size=1024, output_size=10):
    """Create dummy dataset"""
    X = torch.randn(num_samples, input_size)
    y = torch.randint(0, output_size, (num_samples,))
    return TensorDataset(X, y)


def add_argument():
    parser = argparse.ArgumentParser(description="DeepSpeed Test")

    # DeepSpeed arguments
    parser.add_argument(
        "--local_rank", type=int, default=-1, help="local rank passed from distributed launcher"
    )

    # Training arguments
    parser.add_argument("--batch_size", type=int, default=32)
    parser.add_argument("--epochs", type=int, default=5)

    # Include DeepSpeed configuration arguments
    parser = deepspeed.add_config_arguments(parser)

    args = parser.parse_args()
    return args


def main():
    args = add_argument()

    # Create model
    model = SimpleModel()

    # Create dataset and dataloader
    train_dataset = create_dataset(num_samples=1000)
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)

    # DeepSpeed configuration
    ds_config = {
        "train_batch_size": args.batch_size,
        "gradient_accumulation_steps": 1,
        "optimizer": {"type": "Adam", "params": {"lr": 0.001}},
        "fp16": {"enabled": True},
        "zero_optimization": {"stage": 2},
    }

    # Initialize DeepSpeed
    model_engine, optimizer, train_loader, _ = deepspeed.initialize(
        args=args,
        model=model,
        model_parameters=model.parameters(),
        training_data=train_dataset,
        config=ds_config,
    )

    criterion = nn.CrossEntropyLoss()

    # Training loop
    for epoch in range(args.epochs):
        model_engine.train()
        total_loss = 0.0
        num_batches = 0

        for batch_idx, (data, target) in enumerate(train_loader):
            # Move to GPU
            data = data.to(model_engine.local_rank)
            target = target.to(model_engine.local_rank)

            # Forward pass
            outputs = model_engine(data)
            loss = criterion(outputs, target)

            # Backward pass
            model_engine.backward(loss)
            model_engine.step()

            total_loss += loss.item()
            num_batches += 1

            if batch_idx % 10 == 0 and model_engine.local_rank == 0:
                print(f"Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.4f}")

        avg_loss = total_loss / num_batches
        if model_engine.local_rank == 0:
            print(f"Epoch {epoch} completed. Average Loss: {avg_loss:.4f}")

    if model_engine.local_rank == 0:
        print("Training completed successfully!")


if __name__ == "__main__":
    main()
