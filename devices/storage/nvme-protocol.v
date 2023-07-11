namespace kernel.devices.storage

# LBA = Physical address of a logical block

# Todo: Move all the constants and data structures to a protocol file
constant MAX_CONTROLLER_VERSION = 0x20000 # 2.0.0

constant DOORBELL_REGISTERS_OFFSET = 0x1000

constant SUBMISSION_QUEUE_ENTRY_SIZE_EXPONENT = 6
constant SUBMISSION_QUEUE_ENTRY_SIZE = 64
constant COMPLETION_QUEUE_ENTRY_SIZE_EXPONENT = 4
constant COMPLETION_QUEUE_ENTRY_SIZE = 16

constant IO_QUEUE_SIZE = 1024 # Todo: Could this be decided in the code based on capabilities?

constant CONFIGURATION_ENABLED_BIT = 1
constant STATUS_READY_BIT = 1

constant OPERATION_ADMIN_CREATE_SUBMISSION_QUEUE = 1
constant OPERATION_ADMIN_CREATE_COMPLETION_QUEUE = 5
constant OPERATION_ADMIN_IDENTIFY = 6

constant OPERATION_NVME_WRITE = 1 
constant OPERATION_NVME_READ = 2 

constant QUEUE_PHYSICALLY_CONTIGUOUS = 1
constant QUEUE_INTERRUPT_ENABLED = 2

constant HOST_STATE_INITIALIZING = 0
constant HOST_STATE_IDENTIFYING = 1
constant HOST_STATE_LOADING_NAMESPACE_INFORMATION = 2
constant HOST_STATE_COMPLETE = 3

constant MAX_IDENTIFY_NAMESPACE_COUNT = PAGE_SIZE / 4

constant CONTOLLER_NAMESPACE_ID = 0
constant CONTOLLER_NAMESPACE_ACTIVE = 2

constant LBA_FORMAT_SIZE_MASK = 0xf
constant LBA_SIZE_MASK = 0x00ff0000

plain NvmeRegisters {
	capabilities: u64
	version: u32
	interrupt_mask_set: u32
	interrupt_mask_clear: u32
	configuration: u32
	reserved_1: u32
	status: u32
	reserved_2: u32
	admin_queue_attributes: u32
	admin_submission_queue: u64
	admin_completion_queue: u64
}

pack NvmeCapabilities {
	supported_command_sets: u8
	min_host_page: u32
	max_host_page: u32
	doorbell_stride: u32
	ready_timeout: u32
	admin_queue_size: u32
	queue_size: u32
}

plain NvmeSubmissionHeader {
	operation: u8
	flags: u8
	command_id: u16
}

pack NvmeSubmission {
	inline header: NvmeSubmissionHeader
	data: u8[60] # SUBMISSION_QUEUE_ENTRY_SIZE - sizeof(NvmeSubmissionHeader)
}

pack NvmeDataPointer {
	physical_region_page_1: u64
	physical_region_page_2: u64
}

plain NvmeIdentifyCommand {
	inline header: NvmeSubmissionHeader
	namespace_id: u32
	reserved_1: u64[2]
	data_pointer: NvmeDataPointer
	controller_namespace: u8
	reserved_2: u8
	control_id: u16
	reserved_3: u8[3]
	command_set_id: u8
	reserved_4: u64[2]
}

plain NvmeCreateSubmissionQueueCommand {
	inline header: NvmeSubmissionHeader
	reserved_1: u32[5]
	physical_region_page: u64
	reserved_2: u64
	submission_queue_id: u16
	queue_size: u16
	submission_queue_flags: u16
	completion_queue_id: u16
	reserved_3: u64[2]
}

plain NvmeCreateCompletionQueueCommand {
	inline header: NvmeSubmissionHeader

	reserved_1: u32[5]
	physical_region_page: u64
	reserved_2: u64

	completion_queue_id: u16
	queue_size: u16
	completion_queue_flags: u16
	interrupt_vector: u16
	reserved_3: u64[2]
}

# Todo: Fix member names
plain NvmeReadWriteCommand {
	inline header: NvmeSubmissionHeader
	namespace_id: u32
	reserved: u64
	metadata: u64
	data_pointer: NvmeDataPointer
	slba: u64
	length: u16
	control: u16
	dsmgmt: u32
	reftag: u32
	apptag: u16
	appmask: u16
}

pack NvmeCompletion {
   command_specification: u32
   resource: u32 # Todo: Wrong name?

   submission_queue_head: u16 # Where the head of the submission queue is now? So in other words, how much has been processed.
	submission_queue_id: u16 # Submission queue that caused this completion

   command_id: u16 # Which command was completed?
   status: u16
}

plain NvmeIdentifyNamespace {
	namespace_size: u64
	namespace_capacity: u64
	reserved_1: u8[10]
	formatted_lba_size: u8
	reserved_2: u8[100]
	padding_1: u8
	lba_formats: u32[16]
	reserved_3: u64[488]
}

plain NvmeIdentifyNamespaceRequestUserdata {
	identify_data_physical_address: link
	identify_data: NvmeIdentifyNamespace
	active_namespace: NvmeNamespace

	init(identify_data_physical_address: link, identify_data: NvmeIdentifyNamespace, active_namespace: NvmeNamespace) {
		this.identify_data = identify_data
		this.identify_data_physical_address = identify_data_physical_address
		this.active_namespace = active_namespace
	}
}