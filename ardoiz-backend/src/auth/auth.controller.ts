import { Body, Controller, Post, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { RequestOtpDto } from './dto/request-otp.dto';
import { VerifyOtpDto } from './dto/verify-otp.dto';
import { SetupPinDto } from './dto/setup-pin.dto';
import { LoginDto } from './dto/login.dto';
import { RefreshTokenDto } from './dto/refresh-token.dto';
import { ChangePinDto } from './dto/change-pin.dto';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import { CurrentUser } from './decorators/current-user.decorator';
import { AuthenticatedUser } from './strategies/jwt.strategy';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // 10 demandes / 5 min par IP (large : plusieurs commercants peuvent partager
  // la meme IP d'operateur). La protection contre le "SMS bombing" d'un numero
  // donne est assuree par AuthService : un seul code par numero et par minute.
  @Throttle({ default: { limit: 10, ttl: 300_000 } })
  @Post('otp/request')
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.authService.requestOtp(dto.phone);
  }

  // 10 tentatives / 5 min par IP : le code a 6 chiffres expire deja au bout
  // de 5 minutes, mais sans limite de requetes un attaquant pourrait tenter
  // les 10000 combinaisons avant expiration.
  @Throttle({ default: { limit: 10, ttl: 300_000 } })
  @Post('otp/verify')
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto.phone, dto.code);
  }

  @Post('pin/setup')
  setupPin(@Body() dto: SetupPinDto) {
    return this.authService.setupPin(dto.otpSessionToken, dto.businessName, dto.pin);
  }

  // Le verrouillage de compte (auth.service.ts) protege deja le PIN apres 5
  // echecs, mais une limite par IP evite qu'un attaquant essaie des numeros
  // de telephone differents pour contourner le verrouillage par compte.
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('login')
  login(@Body() dto: LoginDto) {
    return this.authService.login(dto.phone, dto.pin);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('pin/change')
  changePin(@CurrentUser() user: AuthenticatedUser, @Body() dto: ChangePinDto) {
    return this.authService.changePin(user.id, dto.currentPin, dto.newPin);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('logout')
  logout(@CurrentUser() user: AuthenticatedUser) {
    return this.authService.logout(user.id);
  }
}
