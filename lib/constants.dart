import 'package:flutter/material.dart';

class AppConstants {
  static const String baseUrl = 'http://172.19.9.152:5000';

  static String fontFamily = 'RedHatDisplay';

  static const double fontSizeDefault = 16.0;
  static const double fontSizeSmall = 14.0;
  static const double fontSizeLarge = 20.0;
  

  static const FontWeight fontWeightRegular = FontWeight.w400;
  static const FontWeight fontWeightMedium = FontWeight.w500;
  static const FontWeight fontWeightBold = FontWeight.w700;

  // Font colors
  static const Color primaryColor = Color(0xff7030a0);
  //static const Color primaryColor = Colors.teal;
  static const Color errorColor = Color.fromARGB(255, 255, 0, 0);
  static const Color fontColorPrimary = Colors.black;
  static const Color fontColorWhite = Colors.white;
  static const Color fontColorSecondary = Colors.grey;
  // static const Color fontColorAccent = Colors.blue;
  static const Color tabHeader = Color(0xffbc9cfb);
  // static const Color tabIdValue = Color(0xffdecdff);
  // static const Color tabValues = Color(0xffece3ff);
  // static const Color mealTypeFontColor = Color(0xffffde59);
  // static const Color marqueeContainer = Color(0xffe6eeeb);
  // static const Color dateRangeContainer = Color(0xffffffff);
  // Background colors
  static const Color backgroundColor = Colors.white;
  static const LinearGradient bgGradient = LinearGradient(
    colors: [Colors.purple, Colors.deepPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const Color splashBackgroundColor = AppConstants.primaryColor;

  // Image assets
  static const String logoImage = 'assets/Logo.png';
  static const String purpleLogo = 'assets/PurpleLogo.png';
  static const String loginScreenImage = 'assets/loginImage.png';
  static const double padding = 10.0;
  static const BoxDecoration cardDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(10)),
    boxShadow: [
      BoxShadow(
        color: Colors.grey,
        blurRadius: 5,
        offset: Offset(0, 2),
      ),
    ],
  );

  static TextStyle superHeadingStyle = TextStyle(
    color: AppConstants.fontColorWhite,
    fontSize: 18,
    fontWeight: FontWeight.bold,
    fontFamily: AppConstants.fontFamily,
  );
  static TextStyle headingStyle = TextStyle(
    color: AppConstants.primaryColor,
    fontSize: 20,
    fontWeight: FontWeight.bold,
    fontFamily: AppConstants.fontFamily,
  );
  static TextStyle welcomeheadingStyle = TextStyle(
    color: AppConstants.fontColorPrimary,
    fontSize: 18,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.w500,
  );
  static TextStyle loginTextStyle = TextStyle(
    color: AppConstants.fontColorWhite,
    fontFamily: AppConstants.fontFamily,
    fontWeight: fontWeightBold,
    fontSize: 22,
  );
  static TextStyle loginBtnTextStyle = TextStyle(
    fontSize: 18,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.fontColorWhite,
    fontWeight: fontWeightBold,
  );

  static TextStyle normalWhiteBoldFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: AppConstants.fontColorWhite,
  );
  static TextStyle normalWhiteFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.fontColorWhite,
  );

  static TextStyle drawerHeaderStyle = TextStyle(
    fontSize: 24,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );
  static TextStyle drawerMiniHeaderStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.w500,
    color: Colors.white,
  );
  static TextStyle selectedButtonFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: AppConstants.primaryColor,
  );
  static TextStyle notSelectedButtonFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static TextStyle normalBoldFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: AppConstants.fontColorPrimary,
  );
  static TextStyle normalFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.fontColorPrimary,
  );
  static TextStyle normalGreyFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.fontColorSecondary,
  );
  static TextStyle errorFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.errorColor,
  );

  static TextStyle boldPurpleFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    fontWeight: FontWeight.bold,
    color: AppConstants.primaryColor,
  );
  static TextStyle normalPurpleFontStyle = TextStyle(
    fontSize: 16,
    fontFamily: AppConstants.fontFamily,
    color: AppConstants.primaryColor,
  );
}
