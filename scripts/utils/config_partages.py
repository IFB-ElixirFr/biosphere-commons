import json
import os
import argparse
from subprocess import Popen

parser = argparse.ArgumentParser()
parser.add_argument("share_params", help="share parameter in json (e.g. {<name_share>:<endpoint>,...}")
parser.add_argument("-s", "--src",
                    help="source of mount directory (default=/var/autofs)")
parser.add_argument("-d", "--dst",
                    help="destination of mount directory (default=/ifb/data)")
args = parser.parse_args()


def config_shares(data_manila_export, src_dir="/var/autofs/ifb", dst_dir="/ifb/data"):
    data = json.loads(data_manila_export)
    os.makedirs(src_dir, exist_ok=True)
    os.makedirs(dst_dir, exist_ok=True)
    with open('/etc/auto.master', 'a') as f:
        f.write('\n' + src_dir + ' /etc/auto.ifb_share' + '\n')

    ifb_manila_file = open("/etc/auto.ifb_share", "w")
    for k, v in data.items():
        if k == "ifb_proxy_enabled":
            with open('/etc/profile.d/ifb.sh', 'a') as ifb_file:
                ifb_file.write('export ifb_proxy_enabled="true"')
        else:
            src = src_dir + "/" + k
            dst = dst_dir + "/" + k
            os.symlink(src, dst)
            if 'opts' in v.keys() and v['opts']:
                params = "-fstype=" + v['protocol'] + "," + v['access_level'] + "," + v['opts']
            else:
                params = "-fstype=" + v['protocol'] + "," + v['access_level']
            ifb_manila_file.write(k + " " + params + " " + v['endpoint'] + "\n")
    ifb_manila_file.close()
    Popen(['service', 'autofs', 'restart'])


if __name__ == '__main__':
    if args.src and args.dst:
        config_shares(args.share_params, src_dir=args.src, dst_dir=args.dst)
    elif args.src and not args.dst:
        config_shares(args.share_params, src_dir=args.src)
    elif not args.src and args.dst:
        config_shares(args.share_params, dst_dir=args.dst)
    else:
        config_shares(args.share_params)
