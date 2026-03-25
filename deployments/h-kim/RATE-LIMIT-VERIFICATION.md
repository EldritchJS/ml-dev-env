# 100 Gbps Rate Limit Verification Results

## Test Date: 2026-03-25

## Summary

Successfully verified that 100 Gbps rate limits are applied and actively limiting network performance during NCCL benchmarks.

## Rate Limit Configuration

- **Rate per NIC:** 100 Gbps (all 8 Traffic Classes)
- **NICs per node:** 4 (eno5np0, eno6np0, eno7np0, eno8np0)
- **Theoretical max per node:** 400 Gbps = 50 GB/s
- **Nodes tested:** 8 H100 nodes (32 GPUs total)

## Benchmark Results

### Gold Standard (No Rate Limit)
- **Peak bandwidth:** ~194 GB/s (8 GB messages)
- **Configuration:** Same hardware, no NIC rate limiting

### With 100 Gbps Rate Limit
- **Peak bandwidth:** 39.06 GB/s (8 GB messages)
- **Average bandwidth:** 38.85 GB/s
- **Performance reduction:** 79.9% (194 → 39 GB/s)

### Detailed Results (8-node, 32 GPUs)

```
 size(MB)   tavg(usec)    tmin(usec)    tmax(usec)  avgbw(GB/sec)  maxbw(GB/sec)  minbw(GB/sec)
    0.10      740.3          605.3         6288.5          0.26           0.32           0.03
    0.12      691.5          589.2         1513.7          0.34           0.39           0.15
    0.15      739.9          597.5         2171.8          0.39           0.49           0.13
    0.20      740.7          637.5         1486.4          0.52           0.61           0.26
    0.32      874.2          689.4         6879.0          0.71           0.90           0.09
    0.40      871.1          672.6         8433.0          0.89           1.15           0.09
    0.50      751.9          689.0         1478.9          1.29           1.41           0.66
    0.64      823.5          690.9         5681.7          1.51           1.79           0.22
    0.80      838.1          692.8         5360.5          1.85           2.24           0.29
    1.00      801.7          718.3         1354.9          2.42           2.70           1.43
    1.25      870.9          711.8         5348.4          2.78           3.40           0.45
    1.50      787.3          714.4         1337.6          3.69           4.07           2.17
    2.00      816.8          712.4         1585.1          4.74           5.44           2.44
    3.16      829.4          752.4         1353.2          7.38           8.14           4.52
    4.00      824.9          782.1         1136.9          9.40           9.91           6.82
    5.00      888.2          814.3         2651.4         10.91          11.90           3.65
    6.40      938.4          852.1         4688.1         13.21          14.55           2.65
    8.00      968.1          896.1         3766.8         16.01          17.30           4.11
   10.00      993.4          954.6         1023.2         19.50          20.30          18.94
   12.50     1276.1         1120.8         2695.9         18.98          21.61           8.98
   15.00     1340.8         1183.0         3335.8         21.68          24.57           8.71
   20.00     1595.3         1380.9         4195.5         24.29          28.06           9.24
   31.60     1880.3         1843.9         1960.6         32.56          33.20          31.23
   40.00     2633.9         2354.9         6974.6         29.42          32.91          11.11
   50.00     3038.4         2796.7         6828.8         31.88          34.64          14.19
   64.00     3797.4         3493.2         7193.0         32.65          35.50          17.24
   80.00     4621.5         4315.6         6323.3         33.54          35.92          24.51
  100.00     5712.5         5412.0         6827.7         33.92          35.80          28.38
  125.00     7580.5         6632.4        11699.6         31.95          36.52          20.70
  160.00     8759.9         8458.7        10681.7         35.39          36.65          29.02
  200.00    10966.4        10616.9        11550.3         35.34          36.50          33.55
  250.00    13609.3        13308.3        13984.0         35.59          36.40          34.64
  316.00    16921.4        16459.9        17248.8         36.18          37.20          35.50
  400.00    20977.4        20660.9        21605.3         36.94          37.51          35.87
  500.00    26185.4        25033.3        30486.1         37.00          38.70          31.78
  640.00    32646.0        32271.1        33327.7         37.98          38.42          37.21
  800.00    40324.4        39898.1        41203.3         38.44          38.85          37.62
 1000.00    50209.2        49438.4        51264.6         38.59          39.19          37.79
 1250.00    64428.1        62903.8        67586.8         37.59          38.50          35.83
 1600.00    81555.7        80290.7        85033.4         38.01          38.61          36.46
 2000.00    101956.2        99500.9        104884.9         38.01          38.94          36.95
 2500.00    126048.9        125325.7        126481.6         38.43          38.65          38.30
 3160.00    158078.5        156633.2        159239.3         38.73          39.09          38.45
 4000.00    200526.2        198809.4        202216.3         38.65          38.98          38.33
 5000.00    249656.6        248318.0        251884.8         38.80          39.01          38.46
 6400.00    319129.4        317314.8        320887.4         38.86          39.08          38.64
 8000.00    398998.2        396793.6        401590.1         38.85          39.06          38.60
```

## Analysis

The results clearly demonstrate that the 100 Gbps rate limit is being enforced:

1. **Bandwidth plateau:** Performance plateaus at ~39 GB/s regardless of message size
2. **Expected bottleneck:** Network is now the bottleneck (previously was ~194 GB/s)
3. **Hardware enforcement:** Rate limiting is enforced in the NIC firmware (no CPU overhead)
4. **Per-NIC limit confirmed:** 100 Gbps × 4 NICs = 400 Gbps = 50 GB/s theoretical max
5. **Measured 39 GB/s:** Reasonable given RDMA overhead, protocol efficiency, and multi-node coordination

## Verification Method

1. Deployed rate limit DaemonSet with NVIDIA OFED image
2. Applied `mlnx_qos --ratelimit=100,100,100,100,100,100,100,100` to all 4 NICs
3. Ran gold standard NCCL all-reduce benchmark on 8 nodes (32 GPUs)
4. Compared results to baseline performance without rate limiting

## Rate Limit Status

All 8 H100 nodes have active 100 Gbps rate limits:
- moc-r4pcc02u05 ✓
- moc-r4pcc02u32 ✓
- moc-r4pcc02u35 ✓
- moc-r4pcc04u09-nairr ✓
- moc-r4pcc04u11-nairr ✓
- moc-r4pcc04u12-nairr ✓
- moc-r4pcc04u16-nairr ✓
- moc-r4pcc04u25-nairr ✓

Rate limits persist until NIC reset or system reboot.

## Removing Rate Limits

To remove the rate limits and restore full performance:

```bash
kubectl delete daemonset apply-100g-rate-limit -n default
```

Then manually reset each NIC or reboot nodes to clear the hardware configuration.
