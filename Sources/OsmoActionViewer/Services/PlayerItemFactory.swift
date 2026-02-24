import AVFoundation

enum PlayerItemFactory {
    static func makeItem(for recording: Recording) -> AVPlayerItem {
        AVPlayerItem(asset: makeAsset(for: recording))
    }

    static func makeAsset(for recording: Recording) -> AVAsset {
        guard recording.segmentURLs.count > 1 else {
            return AVURLAsset(url: recording.segmentURLs[0])
        }

        let composition = AVMutableComposition()
        var cursor = CMTime.zero

        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        for (index, url) in recording.segmentURLs.enumerated() {
            let asset = AVURLAsset(url: url)
            let duration = asset.duration
            let timeRange = CMTimeRange(start: .zero, duration: duration)

            if let videoTrack = asset.tracks(withMediaType: .video).first {
                try? compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: cursor)
                if index == 0 {
                    compositionVideoTrack?.preferredTransform = videoTrack.preferredTransform
                }
            }

            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                try? compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            }

            cursor = CMTimeAdd(cursor, duration)
        }

        return composition
    }
}
