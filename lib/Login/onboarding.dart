import 'package:flutter/material.dart';
import 'package:patroltracking/Login/login.dart';
import 'package:patroltracking/constants.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  _OnboardingScreenState createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemCount: 3,
                  itemBuilder: (context, index) => _buildOnboardingPage(index),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 50.0),
                child: _buildPageIndicator(),
              ),
            ],
          ),
          Positioned(
            top: 40.0,
            right: 16.0,
            child: TextButton(
              onPressed: () {
                if (_currentPage == 2) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => LoginScreen()),
                  );
                } else {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.ease,
                  );
                }
              },
              child: Text(
                _currentPage == 2 ? 'Get Started' : 'Next',
                style: AppConstants.selectedButtonFontStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOnboardingPage(int index) {
    final List<String> titles = [
      'Welcome to PatrolTracking',
      'Track Your Patrols',
      'Stay Secure & Efficient'
    ];
    final List<String> descriptions = [
      'Seamlessly manage and track all your patrol routes.',
      'Log and review patrol data in real-time.',
      'Ensure security and efficiency at every step.'
    ];
    final List<String> images = [
      'assets/Onboard2.png',
      'assets/onboard3.png',
      'assets/onboard4.png'
    ];

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            images[index],
            height: 300,
          ),
          const SizedBox(height: 24),
          Text(
            titles[index],
            style: AppConstants.headingStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            descriptions[index],
            style: AppConstants.normalFontStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) => _indicator(index == _currentPage)),
    );
  }

  Widget _indicator(bool isActive) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 10,
      width: isActive ? 20 : 10,
      decoration: BoxDecoration(
        color: isActive
            ? AppConstants.primaryColor
            : AppConstants.fontColorSecondary,
        borderRadius: BorderRadius.circular(5),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
