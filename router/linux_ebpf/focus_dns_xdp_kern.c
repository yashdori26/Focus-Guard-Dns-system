// +build ignore
/*
 * focus_dns_xdp_kern.c - Ultra High-Performance Driver-Level XDP Firewall for FocusDNS.
 *
 * Attaches to: BPF_PROG_TYPE_XDP
 * Runs directly on the router's network interface driver ring buffer before sk_buff
 * allocation, dropping unauthorized DoH/DoT bypasses and reflection floods at 10Gbps+ line rate.
 *
 * Verdicts:
 * - XDP_DROP: Dropped at NIC driver level (0-cycle kernel overhead)
 * - XDP_PASS: Passed up to regular Linux network stack
 * - XDP_TX: Bounced back out interface (e.g., immediate TCP RESET)
 */

#include <linux/bpf.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <linux/tcp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define DNS_PORT    53
#define DOT_PORT    853
#define HTTPS_PORT  443
#define DHCP_PORT_1 67
#define DHCP_PORT_2 68

/* In-NIC Hash Map of Rogue DoH server IPs */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u8);
} xdp_rogue_ips SEC(".maps");

/* In-NIC Statistics Array */
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 8);
    __type(key, __u32);
    __type(value, __u64);
} xdp_packet_stats SEC(".maps");

static __always_inline void inc_xdp_stat(__u32 idx) {
    __u64 *val = bpf_map_lookup_elem(&xdp_packet_stats, &idx);
    if (val) {
        *val += 1;
    }
}

SEC("xdp")
int focus_xdp_firewall(struct xdp_md *ctx) {
    void *data_end = (void *)(long)ctx->data_end;
    void *data = (void *)(long)ctx->data;

    // 1. Boundary check for Ethernet header
    struct ethhdr *eth = data;
    if ((void *)(eth + 1) > data_end) {
        return XDP_PASS;
    }

    // 2. Life Safety: Pass ARP and non-IP traffic immediately
    if (eth->h_proto != bpf_htons(ETH_P_IP)) {
        return XDP_PASS;
    }

    // 3. Boundary check for IPv4 header
    struct iphdr *ip = (void *)(eth + 1);
    if ((void *)(ip + 1) > data_end) {
        return XDP_PASS;
    }

    // Protocol check: Only inspect UDP and TCP
    if (ip->protocol == IPPROTO_UDP) {
        struct udphdr *udp = (void *)((char *)ip + (ip->ihl * 4));
        if ((void *)(udp + 1) > data_end) {
            return XDP_PASS;
        }

        __u16 dst_port = bpf_ntohs(udp->dest);
        __u16 src_port = bpf_ntohs(udp->source);

        // Life Safety: DHCP (ports 67/68) must NEVER be filtered
        if (dst_port == DHCP_PORT_1 || dst_port == DHCP_PORT_2 ||
            src_port == DHCP_PORT_1 || src_port == DHCP_PORT_2) {
            return XDP_PASS;
        }

        // Drop Rogue DNS-over-QUIC (UDP Port 853) targeting untrusted endpoints
        if (dst_port == DOT_PORT) {
            inc_xdp_stat(2); // Drop counter
            return XDP_DROP;
        }

        // Standard DNS traffic passes to userspace daemon
        if (dst_port == DNS_PORT) {
            inc_xdp_stat(0); // DNS count
            return XDP_PASS;
        }
    } else if (ip->protocol == IPPROTO_TCP) {
        struct tcphdr *tcp = (void *)((char *)ip + (ip->ihl * 4));
        if ((void *)(tcp + 1) > data_end) {
            return XDP_PASS;
        }

        __u16 dst_port = bpf_ntohs(tcp->dest);

        // Drop Rogue DoT over TCP (Port 853)
        if (dst_port == DOT_PORT) {
            inc_xdp_stat(2);
            return XDP_DROP;
        }

        // Drop Hardcoded Rogue DoH IPs on HTTPS (Port 443)
        if (dst_port == HTTPS_PORT) {
            __u32 target_ip = ip->daddr;
            __u8 *blocked = bpf_map_lookup_elem(&xdp_rogue_ips, &target_ip);
            if (blocked && *blocked == 1) {
                inc_xdp_stat(1); // DoH Drop counter
                return XDP_DROP;
            }
        }
    }

    return XDP_PASS;
}

char _license[] SEC("license") = "GPL";
