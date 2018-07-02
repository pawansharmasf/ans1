# Run offline compaction
{{ javalocation.stdout }} -Dtar.memoryMapped=true -Xms$1 -Xmx$1 -jar $2/oak-run-1.4.11.jar checkpoints $3/repository/segmentstore >> $2/compaction-log.txt
{{ javalocation.stdout }} -Dtar.memoryMapped=true -Xms$1 -Xmx$1 -jar $2/oak-run-1.4.11.jar checkpoints $3/repository/segmentstore rm-unreferenced >> $2/compaction-log.txt
{{ javalocation.stdout }} -Dtar.memoryMapped=true -Xms$1 -Xmx$1 -jar $2/oak-run-1.4.11.jar compact $3/repository/segmentstore >> $2/compaction-log.txt

