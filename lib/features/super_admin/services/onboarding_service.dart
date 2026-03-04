import '../data/super_admin_repo.dart';

class OnboardingService {
  OnboardingService(this._repo);

  final SuperAdminRepo _repo;

  Future<void> claimInvite({
    required String uid,
    required String inviteCode,
  }) async {
    await _repo.claimInviteWithCode(uid: uid, inviteCode: inviteCode);
  }
}
