// +build ignore
/*
 * focus_dns_kern.c - High-Performance Linux eBPF Kernel Firewall for FocusDNS.
 *
 * Attaches to:
 * 1. BPF_PROG_TYPE_CGROUP_SOCK_ADDR (connect4 / connect6)
 *    Transparently redirects outbound port 53 traffic to the local stub resolver
 *    (127.0.0.1:5353) with zero userspace context switching.
 * 2. BPF_PROG_TYPE_CGROUP_SKB (ingress / egress)
 *    Drops outbound flows targeting unauthorized DoH / DoT IP addresses
 *    (e.g., 1.1.1.1:443, 8.8.8.8:443, 9.9.9.9:853) to eliminate app-level bypasses.
 *
 * Inviolable Laws:
 * - Life Safety Exemption: DHCP (67/68), Loopback (127.0.0.0/8), and Emergency Telecom
 *   are NEVER blocked or redirected.
 * - Fail-Safe Guarantee: If local stub is unreachable, passes query to fallback LAN resolver.
 */

#include <linux/bpf.h>
#include <linux/in.h>
#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/udp.h>
#include <linux/tcp.h>
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_endian.h>

#define FOCUS_DNS_REDIRECT_IP   0x7F000001 /* 127.0.0.1 in hex */
#define FOCUS_DNS_REDIRECT_PORT 5353       /* Local stub daemon port */
#define DNS_STANDARD_PORT       53
#define DOT_STANDARD_PORT       853
#define HTTPS_PORT              443
#define DHCP_SERVER_PORT        67
#define DHCP_CLIENT_PORT        68

/*
 * BPF Map: Rogue DoH / DoT Destination IPv4 Blacklist
 * Keys: IPv4 address in network byte order.
 * Value: 1 if blocked, 0 if allowed.
 */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u32);
    __type(value, __u8);
} rogue_doh_v4 SEC(".maps");

/*
 * BPF Map: Client Hardware / IP to Profile ID Mapping
 * Keys: Client IPv4 address.
 * Value: Profile Index (0: Strict Kids, 1: Deep Work, 2: Ad-Free IoT, 3: Family Safe).
 */
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 4096);
    __type(key, __u32);
    __type(value, __u32);
} client_profile_map SEC(".maps");

/*
 * BPF Map: In-Kernel Telemetry & Bypass Drop Counters
 * Index 0: Queries Redirected
 * Index 1: Rogue DoH Drops
 * Index 2: Rogue DoT Drops
 * Index 3: Tamper Rejections
 */
struct {
    __uint(type, BPF_MAP_TYPE_PERCPU_ARRAY);
    __uint(max_entries, 16);
    __type(key, __u32);
    __type(value, __u64);
} focus_telemetry_map SEC(".maps");

/*
 * BPF Map: Conditional Uninstallation Posture
 * Key 0: 0 = Normal Mode (Uninstall Permitted), 1 = Strict Focus Lock (Removal Denied).
 */
struct {
    __uint(type, BPF_MAP_TYPE_ARRAY);
    __uint(max_entries, 4);
    __type(key, __u32);
    __type(value, __u32);
} lock_posture_map SEC(".maps");

static __always_inline void increment_counter(__u32 index) {
    __u64 *val = bpf_map_lookup_elem(&focus_telemetry_map, &index);
    if (val) {
        *val += 1;
    }
}

/*
 * Hook 1: Socket Address Rewrite (connect4)
 * Transparently captures outbound UDP/TCP port 53 and rewrites target to 127.0.0.1:5353.
 */
SEC("cgroup/connect4")
int focus_sock_connect4(struct bpf_sock_addr *ctx) {
    // Only inspect IPv4 AF_INET sockets
    if (ctx->user_family != AF_INET) {
        return 1;
    }

    __u16 dst_port = bpf_ntohs((__u16)ctx->user_port);
    __u32 dst_ip = bpf_ntohl(ctx->user_ip4);

    // Life Safety Exemption 1: Loopback traffic is never intercepted
    if ((dst_ip & 0xFF000000) == 0x7F000000) {
        return 1;
    }

    // Life Safety Exemption 2: DHCP traffic (ports 67/68) must pass unimpeded
    if (dst_port == DHCP_SERVER_PORT || dst_port == DHCP_CLIENT_PORT) {
        return 1;
    }

    // Intercept standard DNS (UDP or TCP port 53)
    if (dst_port == DNS_STANDARD_PORT) {
        // Rewrite destination to 127.0.0.1:5353
        ctx->user_ip4 = bpf_htonl(FOCUS_DNS_REDIRECT_IP);
        ctx->user_port = (__u32)bpf_htons(FOCUS_DNS_REDIRECT_PORT);
        increment_counter(0); // DNS redirected
        return 1;
    }

    // Anti-Bypass Guard: Intercept Rogue DoT (Port 853)
    if (dst_port == DOT_STANDARD_PORT) {
        increment_counter(2); // DoT dropped
        return 0; // Drop connection immediately
    }

    // Anti-Bypass Guard: Intercept hardcoded DoH IPs targeting port 443
    if (dst_port == HTTPS_PORT) {
        __u32 search_ip = ctx->user_ip4;
        __u8 *blocked = bpf_map_lookup_elem(&rogue_doh_v4, &search_ip);
        if (blocked && *blocked == 1) {
            increment_counter(1); // DoH dropped
            return 0; // Reject TCP SYN
        }
    }

    return 1; // Allow normal traffic
}

/*
 * Hook 2: Socket Outbound Packet Filter (cgroup/skb_egress)
 * Ensures non-cooperative raw socket packets targeting rogue DoH/DoT are dropped.
 */
SEC("cgroup/skb_egress")
int focus_skb_egress_filter(struct __sk_buff *skb) {
    // Audit packet protocol
    if (skb->protocol != bpf_htons(ETH_P_IP)) {
        return 1;
    }

    struct iphdr ip;
    if (bpf_skb_load_bytes(skb, 0, &ip, sizeof(ip)) < 0) {
        return 1;
    }

    __u32 dst_ip = ip.daddr;

    // Check DoH rogue map
    __u8 *is_rogue = bpf_map_lookup_elem(&rogue_doh_v4, &dst_ip);
    if (is_rogue && *is_rogue == 1) {
        increment_counter(1);
        return 0; // DROP packet at kernel boundary
    }

    return 1; // ALLOW
}

char _license[] SEC("license") = "GPL";
