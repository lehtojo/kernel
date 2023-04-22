namespace kernel

pack Credentials {
	uid: u32
	gid: u32
	euid: u32
	egid: u32

	shared new(uid: u32, gid: u32, euid: u32, egid: u32): Credentials {
		return pack { uid: uid, gid: gid, euid: euid, egid: egid } as Credentials
	}
}