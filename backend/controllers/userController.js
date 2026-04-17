const User = require('../models/User');

// GET USER PROFILE
const getUserProfile = async (req, res) => {
  try {
    const { userId } = req.params;

    const user = await User.findById(userId).select('-password');

    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
    }

    res.json(user);
  } catch (error) {
    console.error('Get profile error:', error.message);
    res.status(500).json({ error: 'Profil alınamadı' });
  }
};

// UPDATE USER PROFILE
const updateUserProfile = async (req, res) => {
  try {
    const { userId } = req.params;

    const {
      shoeSize,
      clothingSize,
      height,
      weight,
      style,
      onboardingCompleted,
    } = req.body;

    const user = await User.findByIdAndUpdate(
      userId,
      {
        shoeSize,
        clothingSize,
        height,
        weight,
        style,
        onboardingCompleted,
      },
      { new: true }
    ).select('-password');

    if (!user) {
      return res.status(404).json({ error: 'Kullanıcı bulunamadı' });
    }

    res.json(user);
  } catch (error) {
    console.error('Update profile error:', error.message);
    res.status(500).json({ error: 'Profil güncellenemedi' });
  }
};

module.exports = {
  getUserProfile,
  updateUserProfile,
};